import FolioCore
import SwiftUI

@main
struct FolioApp: App {
    init() {
        // Also proves FolioCore is linked into the app target: remove the
        // package dependency and this file stops compiling.
        AppLog.general.info("FolioCore \(FolioCore.version, privacy: .public)")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
