/// Platform-agnostic domain logic for Folio.
///
/// This package has no UI and no Apple-framework dependencies beyond
/// Foundation, so it is testable with `swift test` in seconds — no simulator.
/// Put domain types, protocols, and business rules here; keep SwiftUI in the
/// app target.
public enum FolioCore {
    /// Package version, used by the smoke test to prove the target is wired.
    public static let version = "0.1.0"
}
