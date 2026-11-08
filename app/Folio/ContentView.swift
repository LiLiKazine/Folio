import SwiftUI

/// Placeholder UI. This is the first file to delete when real work starts —
/// nothing else in the template depends on it, and no test asserts on it.
struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "swift")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Folio")
                .font(.title)
        }
        .padding(40)
        .task {
            AppLog.general.info("Folio launched")
        }
    }
}

#Preview {
    ContentView()
}
