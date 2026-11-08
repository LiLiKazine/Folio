#if os(iOS)
    import SwiftUI

    /// The bar along the bottom of the Library while the iPad selects Books:
    /// one destructive action that deletes every selected Book.
    struct LibrarySelectionBar: View {
        let count: Int
        let onDelete: () -> Void

        var body: some View {
            HStack {
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Text("Delete (\(count))")
                }
                .disabled(count == 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }
#endif
