import Foundation

/// Port reporting free space where the Library will write.
public protocol StorageCapacity: Sendable {
    func availableBytes(at url: URL) throws -> Int64
}

public struct VolumeStorageCapacity: StorageCapacity {
    public init() {}

    public func availableBytes(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values.volumeAvailableCapacityForImportantUsage ?? 0
    }
}

public struct FixedStorageCapacity: StorageCapacity {
    public var bytes: Int64

    public init(bytes: Int64) {
        self.bytes = bytes
    }

    public func availableBytes(at url: URL) throws -> Int64 { bytes }
}
