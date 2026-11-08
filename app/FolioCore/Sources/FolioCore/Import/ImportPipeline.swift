import Foundation

/// Why an Import stopped without a Book.
public struct ImportFailure: Error, Equatable {
    public let reason: ImportFailureReason

    public init(reason: ImportFailureReason) { self.reason = reason }
}

/// Turns one Source into one Book folder atomically: every Page copied and the
/// Cover rendered, or nothing left behind.
public struct ImportPipeline: Sendable {
    private static let stagingName = ".staging"
    private static let pagesName = "pages"
    private static let expandedName = "expanded"

    let booksDirectory: URL
    private let storage: StorageCapacity
    /// FileManager is not `Sendable`, but Apple documents its methods as thread-safe
    /// when no delegate is set; the pipeline never sets one.
    nonisolated(unsafe) private let fileManager: FileManager

    public init(
        booksDirectory: URL,
        storage: StorageCapacity = VolumeStorageCapacity(),
        fileManager: FileManager = .default
    ) {
        self.booksDirectory = booksDirectory
        self.storage = storage
        self.fileManager = fileManager
    }

    var stagingRoot: URL { booksDirectory.appending(path: Self.stagingName) }

    /// Staging lives at `<booksDirectory>/.staging/<bookID>`; the final folder is `<booksDirectory>/<bookID>`.
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
        let staging = stagingRoot.appending(path: folderName, directoryHint: .isDirectory)
        do {
            let pages = try await stagePages(from: source, into: staging, progress: progress)
            try renderCover(
                from: staging.appending(path: Self.pagesName), pages: pages, in: staging)
            try fileSystem {
                try fileManager.moveItem(
                    at: staging, to: booksDirectory.appending(path: folderName))
            }
            return Book(
                id: bookID, title: title, folderName: folderName, pages: pages,
                coverFileName: CoverImage.fileName, importedAt: importedAt,
                lastOpenedAt: nil, readingPosition: nil)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    /// Deletes every folder under `.staging`. An item that cannot be deleted does not
    /// stop the rest; the first such error is thrown once all have been tried.
    public func removeAllStaging() throws {
        guard fileManager.fileExists(atPath: stagingRoot.path) else { return }
        var firstError: (any Error)?
        for item in try fileManager.contentsOfDirectory(
            at: stagingRoot, includingPropertiesForKeys: nil)
        {
            do {
                try fileManager.removeItem(at: item)
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError { throw firstError }
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
            try fileSystem {
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

    /// Runs a file-system operation, mapping out-of-space to `.notEnoughStorage`
    /// and any other failure to `.storageFailure`.
    private func fileSystem(_ operation: () throws -> Void) throws {
        do {
            try operation()
        } catch {
            throw ImportFailure(
                reason: Self.isOutOfSpace(error) ? .notEnoughStorage : .storageFailure)
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
