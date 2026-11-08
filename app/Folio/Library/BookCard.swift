import FolioCore
import SwiftUI

/// One Book in the Library grid: its Cover, Title, and Page count or Reading Position.
struct BookCard: View {
    let book: Book
    let coverURL: URL
    /// Shows the selection highlight: the Mac's selected Book, or a Book the iPad selected.
    var isSelected = false
    /// Adds a checkmark badge to the Cover, for a Book the iPad selected.
    var showsCheckmark = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CoverView(url: coverURL)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(Color.accentColor, lineWidth: 3)
                            .padding(-4)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if showsCheckmark {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .padding(6)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.bottom, 4)
            Text(book.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            if let position = book.readingPosition, !book.pages.isEmpty {
                let page = min(max(position + 1, 1), book.pages.count)
                Text("Page \(page) of \(book.pages.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(page), total: Double(book.pages.count))
                    .progressViewStyle(.linear)
                    .frame(height: 3)
            } else {
                Text("\(book.pages.count) pages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
