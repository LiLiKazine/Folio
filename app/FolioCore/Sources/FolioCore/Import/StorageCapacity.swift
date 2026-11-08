import Foundation

public enum StorageCapacityError: Error, Equatable {
    case unavailable
}

/// Port reporting free space where the Library will write.
public protocol StorageCapacity: Sendable {
    func availableBytes(at url: URL) throws -> Int64
}

public struct VolumeStorageCapacity: StorageCapacity {
    public init() {}

    public func availableBytes(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let bytes = values.volumeAvailableCapacityForImportantUsage else {
            throw StorageCapacityError.unavailable
        }
        return bytes
    }
}

public struct FixedStorageCapacity: StorageCapacity {
    public var bytes: Int64

    public init(bytes: Int64) {
        self.bytes = bytes
    }

    public func availableBytes(at url: URL) throws -> Int64 { bytes }
}
