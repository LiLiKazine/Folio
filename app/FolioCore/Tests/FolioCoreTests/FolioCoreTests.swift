import Testing
@testable import FolioCore

@Suite("Core smoke")
struct FolioCoreTests {
    @Test("package exposes a version")
    func version() {
        #expect(FolioCore.version == "0.1.0")
    }
}
