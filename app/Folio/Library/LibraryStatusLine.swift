import FolioCore
import SwiftUI

/// A Notice about a failure with no action of the user's behind it, shown as
/// a line above the Library grid instead of a dialog, so it informs without
/// interrupting. The close control removes it.
struct LibraryStatusLine: View {
    let notice: Notice
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(.subheadline.weight(.semibold))
                Text(notice.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Button("Close", systemImage: "xmark", action: onClose)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

#Preview {
    LibraryStatusLine(notice: Notice(storageFailed: .openLibrary)) {}
}
