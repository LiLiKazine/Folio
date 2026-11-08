/// Decides when an Import asked for on the Library screen opens the file picker.
///
/// The system refuses to open the file picker while another dialog (a Notice, a
/// Rename or Delete confirmation) is on the same screen, and never says so. An
/// Import asked for then is remembered here and the picker opens once that
/// dialog has closed. Asking again while waiting still opens it only once.
struct ImportRequestGate: Equatable {
    /// True while an Import was asked for and the picker has not opened yet.
    private(set) var isRequested = false

    /// Records a request for the file picker.
    /// - Parameter canPresent: whether no other dialog is on screen.
    /// - Returns: true when the picker should open now.
    mutating func request(canPresent: Bool) -> Bool {
        isRequested = !canPresent
        return canPresent
    }

    /// Called once the dialogs on screen have closed and settled.
    /// - Returns: true when a waiting request should open the picker now.
    mutating func dialogsCleared() -> Bool {
        guard isRequested else { return false }
        isRequested = false
        return true
    }
}
