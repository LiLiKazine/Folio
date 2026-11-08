import Foundation

/// Why an Import stopped without a Book.
public struct ImportFailure: Error, Equatable {
    public let reason: ImportFailureReason

    public init(reason: ImportFailureReason) { self.reason = reason }
}

/// Turns one Source into one Book folder atomically: every Page copied and the
/// Cover rendered, or nothing left behind.
public struct ImportPipeline: Sendable {
    /// The folder under the system temporary directory used when no item-replacement
    /// directory can be had for the Books directory's volume.
    static let fallbackStagingName = "FolioImport"
    private static let pagesName = "pages"
    private static let expandedName = "expanded"

    let booksDirectory: URL
    private let storage: StorageCapacity
    /// FileManager is not `Sendable`, but Apple documents its methods as thread-safe
    /// when no delegate is set; the pipeline never sets one.
    nonisolated(unsafe) private let fileManager: FileManager
    /// The system temporary directory; the fallback staging folder lives under it.
    private let temporaryDirectory: URL
    /// Returns a fresh directory, owned by one run, on the same volume as the given
    /// Books directory. The run deletes it when it ends.
    private let stagingRootProvider: @Sendable (URL) throws -> URL

    public init(
        booksDirectory: URL,
        storage: StorageCapacity = VolumeStorageCapacity(),
        fileManager: FileManager = .default
    ) {
        self.init(
            booksDirectory: booksDirectory, storage: storage, fileManager: fileManager,
            temporaryDirectory: FileManager.default.temporaryDirectory,
            stagingRootProvider: Self.itemReplacementDirectory(for:))
    }

    /// Test seam: `temporaryDirectory` stands in for the system temporary directory and
    /// `stagingRootProvider` for the item-replacement lookup (throw to force the fallback).
    init(
        booksDirectory: URL,
        storage: StorageCapacity = VolumeStorageCapacity(),
        fileManager: FileManager = .default,
        temporaryDirectory: URL,
        stagingRootProvider: @escaping @Sendable (URL) throws -> URL
    ) {
        self.booksDirectory = booksDirectory
        self.storage = storage
        self.fileManager = fileManager
        self.temporaryDirectory = temporaryDirectory
        self.stagingRootProvider = stagingRootProvider
    }

    /// A fresh system temporary directory on the same volume as `booksDirectory`, so
    /// moving out of it is a rename. The system purges whatever a killed run leaves there.
    static func itemReplacementDirectory(for booksDirectory: URL) throws -> URL {
        try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: booksDirectory, create: true)
    }

    var fallbackStagingRoot: URL {
        temporaryDirectory.appending(path: Self.fallbackStagingName, directoryHint: .isDirectory)
    }

    /// Staging lives at `<staging root>/<bookID>`, where the staging root is a fresh
    /// item-replacement directory for the Books directory's volume (or, if the system
    /// cannot supply one, `<temporary directory>/FolioImport`). The final folder is
    /// `<booksDirectory>/<bookID>`, reached by a single rename that never copies.
    /// `progress` receives (pagesDone, pagesTotal), first call with (0, total).
    /// On any throw, including `CancellationError`, the staging folder is gone and no final folder exists.
    public func run(
        source: URL,
        bookID: BookID,
        title: String,
        importedAt: Date = .now,
        progress: @Sendable (Int, Int) async -> Void
    ) async throws -> Book {
        let folderName = bookID.rawValue.uuidString
        try fileSystem {
            try fileManager.createDirectory(at: booksDirectory, withIntermediateDirectories: true)
        }
        let (stagingRoot, ownsRoot) = try makeStagingRoot()
        defer {
            // Ignored: an owned staging root is a system item-replacement directory,
            // which the system purges; nothing in the Library lists it.
            if ownsRoot { try? fileManager.removeItem(at: stagingRoot) }
        }
        let staging = stagingRoot.appending(path: folderName, directoryHint: .isDirectory)
        do {
            let pages = try await stagePages(from: source, into: staging, progress: progress)
            try renderCover(
                from: staging.appending(path: Self.pagesName), pages: pages, in: staging)
            try fileSystem {
                try rename(staging, to: booksDirectory.appending(path: folderName))
            }
            return Book(
                id: bookID, title: title, folderName: folderName, pages: pages,
                coverFileName: CoverImage.fileName, importedAt: importedAt,
                lastOpenedAt: nil, readingPosition: nil)
        } catch {
            // Ignored: staging is temporary storage nothing in the Library lists; launch
            // clean-up or the system removes what is left, and the user is told `error`.
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    /// Deletes everything under `<temporary directory>/FolioImport`, then the folder
    /// itself. Item-replacement directories are left for the system to purge. An item
    /// that cannot be deleted does not stop the rest; the first such error is thrown
    /// once all have been tried.
    public func removeLeftoverStaging() throws {
        let root = fallbackStagingRoot
        guard fileManager.fileExists(atPath: root.path) else { return }
        var firstError: (any Error)?
        for item in try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            do {
                try fileManager.removeItem(at: item)
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError { throw firstError }
        try fileManager.removeItem(at: root)
    }

    /// The staging root for one run, and whether the run owns (and so deletes) it.
    private func makeStagingRoot() throws -> (URL, owned: Bool) {
        do {
            return (try stagingRootProvider(booksDirectory), true)
        } catch {
            LibraryLog.logger.warning(
                "No item-replacement directory for the Books directory, staging under FolioImport: \(String(describing: error), privacy: .public)"
            )
        }
        let root = fallbackStagingRoot
        try fileSystem {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        }
        return (root, false)
    }

    /// Moves `source` to `destination` with `rename(2)`, failing if `destination` exists.
    /// Unlike `FileManager.moveItem`, this never falls back to copying when the two are
    /// on different volumes, so the Book folder appears whole or not at all.
    private func rename(_ source: URL, to destination: URL) throws {
        let result = source.withUnsafeFileSystemRepresentation { from in
            destination.withUnsafeFileSystemRepresentation { to in
                guard let from, let to else { return EINVAL }
                return renamex_np(from, to, UInt32(RENAME_EXCL)) == 0 ? 0 : errno
            }
        }
        guard result != 0 else { return }
        if result == EXDEV {
            LibraryLog.logger.error(
                "Staging is on a different volume from the Books directory; the Import cannot be moved into place"
            )
        }
        throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO)
    }

    /// Checks storage, then fills `<staging>/pages` with the Source's Pages under their new names.
    /// A zip Source is expanded into `<staging>/expanded` first and its Pages moved, not copied.
    private func stagePages(
        from source: URL, into staging: URL, progress: @Sendable (Int, Int) async -> Void
    ) async throws -> [Page] {
        let isZip = source.pathExtension.lowercased() == "zip"
        let pageFiles: [URL]
        if isZip {
            let archive = try openZip(source)
            try checkStorage(needs: archive.entries.reduce(0) { $0 + Int64($1.uncompressedSize) })
            let expanded = staging.appending(path: Self.expandedName, directoryHint: .isDirectory)
            try fileSystem {
                try fileManager.createDirectory(at: expanded, withIntermediateDirectories: true)
            }
            do {
                try archive.extract(to: expanded)
            } catch {
                throw ImportFailure(
                    reason: error == .unsupported ? .unsupportedZip : .unreadableZip)
            }
            pageFiles = try scan(expanded)
        } else {
            pageFiles = try scan(source)
            try checkStorage(needs: try pageFiles.reduce(0) { $0 + (try fileSize(of: $1)) })
        }

        let pagesFolder = staging.appending(path: Self.pagesName, directoryHint: .isDirectory)
        try fileSystem {
            try fileManager.createDirectory(at: pagesFolder, withIntermediateDirectories: true)
        }
        await progress(0, pageFiles.count)
        var pages: [Page] = []
        for (index, file) in pageFiles.enumerated() {
            let page = Page(
                fileName: String(format: "%04d", index + 1) + "." + file.pathExtension.lowercased())
            let destination = pagesFolder.appending(path: page.fileName)
            try fileSystem(readingSource: !isZip) {
                if isZip {
                    try fileManager.moveItem(at: file, to: destination)
                } else {
                    try fileManager.copyItem(at: file, to: destination)
                }
            }
            pages.append(page)
            await progress(pages.count, pageFiles.count)
            try Task.checkCancellation()
        }
        if isZip {
            try fileSystem {
                try fileManager.removeItem(at: staging.appending(path: Self.expandedName))
            }
        }
        return pages
    }

    private func openZip(_ source: URL) throws -> ZipArchive {
        do {
            return try ZipArchive(url: source)
        } catch {
            throw ImportFailure(reason: error == .unsupported ? .unsupportedZip : .unreadableZip)
        }
    }

    private func scan(_ folder: URL) throws -> [URL] {
        let files: [URL]
        do {
            files = try SourceScanner.pageFiles(in: folder)
        } catch {
            throw ImportFailure(reason: .sourceUnavailable)
        }
        guard !files.isEmpty else { throw ImportFailure(reason: .noImagesFound) }
        return files
    }

    private func fileSize(of file: URL) throws -> Int64 {
        do {
            return Int64(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        } catch {
            throw ImportFailure(reason: .sourceUnavailable)
        }
    }

    /// Fails with `.notEnoughStorage` when the Books directory's volume reports less
    /// free space than `bytes`. When capacity is unknown, the check is skipped.
    private func checkStorage(needs bytes: Int64) throws {
        guard let available = try? storage.availableBytes(at: booksDirectory) else { return }
        if available < bytes { throw ImportFailure(reason: .notEnoughStorage) }
    }

    private func renderCover(from pagesFolder: URL, pages: [Page], in staging: URL) throws {
        guard let first = pages.first else { throw ImportFailure(reason: .noImagesFound) }
        do {
            try CoverImage.render(
                page: pagesFolder.appending(path: first.fileName),
                to: staging.appending(path: CoverImage.fileName))
        } catch {
            throw ImportFailure(reason: .undecodablePage)
        }
    }

    /// Runs a file-system operation, mapping out-of-space to `.notEnoughStorage` and
    /// any other failure to `.storageFailure`. When the operation reads the Source,
    /// a read-side failure (missing file, no permission) is `.sourceUnavailable`.
    private func fileSystem(readingSource: Bool = false, _ operation: () throws -> Void) throws {
        do {
            try operation()
        } catch {
            let reason: ImportFailureReason =
                if Self.isOutOfSpace(error) {
                    .notEnoughStorage
                } else if readingSource, Self.isReadFailure(error) {
                    .sourceUnavailable
                } else {
                    .storageFailure
                }
            throw ImportFailure(reason: reason)
        }
    }

    /// True for errors that mean a file could not be read: Cocoa read-side codes,
    /// or POSIX `ENOENT`/`EACCES`. A Cocoa error is judged by its own code alone, so
    /// a write failure wrapping `EACCES` stays a write failure.
    static func isReadFailure(_ error: any Error) -> Bool {
        let error = error as NSError
        switch error.domain {
        case NSCocoaErrorDomain:
            return [
                NSFileReadNoSuchFileError, NSFileReadNoPermissionError, NSFileReadUnknownError,
                NSFileNoSuchFileError,
            ].contains(error.code)
        case NSPOSIXErrorDomain:
            return error.code == Int(ENOENT) || error.code == Int(EACCES)
        default:
            guard let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError else {
                return false
            }
            return isReadFailure(underlying)
        }
    }

    private static func isOutOfSpace(_ error: any Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain, error.code == NSFileWriteOutOfSpaceError {
            return true
        }
        if error.domain == NSPOSIXErrorDomain, error.code == Int(ENOSPC) { return true }
        guard let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError else {
            return false
        }
        return isOutOfSpace(underlying)
    }
}
