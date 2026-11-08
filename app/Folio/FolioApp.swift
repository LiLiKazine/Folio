import FolioCore
import SwiftUI

@main
struct FolioApp: App {
    init() {
        // Also proves FolioCore is linked into the app target: remove the
        // package dependency and this file stops compiling.
        AppLog.general.info("Folio launched \(BookID().rawValue.uuidString, privacy: .public)")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
