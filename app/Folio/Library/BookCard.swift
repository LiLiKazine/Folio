import FolioCore
import SwiftUI

/// One Book in the Library grid: its Cover, Title, and Page count or Reading Position.
struct BookCard: View {
    let book: Book
    let coverURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CoverView(url: coverURL)
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
    }
}
