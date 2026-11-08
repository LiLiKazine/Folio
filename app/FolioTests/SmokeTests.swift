import Testing

@testable import Folio

/// Proves the test target is wired, runs under Swift 6 strict concurrency, and
/// gives the next test a file to pattern-match. It deliberately asserts on the
/// logging surface rather than on ContentView, which is throwaway sample UI.
@Suite("Smoke")
struct SmokeTests {
    @Test("logging subsystem matches the bundle identifier")
    func loggingSubsystem() {
        #expect(AppLog.subsystem == "io.lilikaine.github.folio")
    }

    @Test("general logger is usable from a concurrent context")
    func loggerIsSendable() async {
        await Task.detached {
            AppLog.general.debug("smoke test")
        }.value
    }
}
