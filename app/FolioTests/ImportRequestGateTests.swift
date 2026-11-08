import Testing

@testable import Folio

@Suite("Import request gate")
struct ImportRequestGateTests {
    @Test("a request with no dialog on screen opens the picker at once")
    func requestWhileFree() {
        var gate = ImportRequestGate()
        let presents = gate.request(canPresent: true)
        #expect(presents)
        #expect(!gate.isRequested)
    }

    @Test("a request while a dialog is on screen waits")
    func requestWhileBlocked() {
        var gate = ImportRequestGate()
        let presents = gate.request(canPresent: false)
        #expect(!presents)
        #expect(gate.isRequested)
    }

    @Test("a waiting request opens the picker once the dialogs close")
    func clearedWhileRequested() {
        var gate = ImportRequestGate()
        _ = gate.request(canPresent: false)
        let presents = gate.dialogsCleared()
        #expect(presents)
        #expect(!gate.isRequested)
    }

    @Test("dialogs closing with no request open nothing")
    func clearedWhileNotRequested() {
        var gate = ImportRequestGate()
        let presents = gate.dialogsCleared()
        #expect(!presents)
        #expect(gate == ImportRequestGate())
    }

    @Test("asking again while waiting still opens the picker once")
    func repeatedRequestsWhileBlocked() {
        var gate = ImportRequestGate()
        let first = gate.request(canPresent: false)
        let second = gate.request(canPresent: false)
        let third = gate.request(canPresent: false)
        #expect(!first && !second && !third)
        let firstClear = gate.dialogsCleared()
        let secondClear = gate.dialogsCleared()
        #expect(firstClear)
        #expect(!secondClear)
    }

    /// The view passes `canPresent: false` while a closing dialog settles.
    @Test("a request while a dialog is still closing is remembered")
    func requestWhileSettling() {
        var gate = ImportRequestGate()
        let isSettling = true
        let presents = gate.request(canPresent: !isSettling)
        #expect(!presents)
        #expect(gate.isRequested)
        let presentsAfterSettle = gate.dialogsCleared()
        #expect(presentsAfterSettle)
    }

    @Test("a waiting request followed by one made while free opens the picker once")
    func waitingThenFreeRequest() {
        var gate = ImportRequestGate()
        _ = gate.request(canPresent: false)
        let presents = gate.request(canPresent: true)
        #expect(presents)
        #expect(!gate.isRequested)
        let presentsAgain = gate.dialogsCleared()
        #expect(!presentsAgain)
    }
}
