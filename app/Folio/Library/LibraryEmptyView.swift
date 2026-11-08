import SwiftUI

/// Shown when the Library has no Books and no Imports.
struct LibraryEmptyView: View {
    let onImport: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No Books yet", systemImage: "books.vertical")
        } description: {
            Text("Import a folder of images, or a zip of one, from Files.")
        } actions: {
            Button("Import a Book", action: onImport)
                .buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    LibraryEmptyView {}
}
