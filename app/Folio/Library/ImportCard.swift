import FolioCore
import SwiftUI

/// One Import that has not produced a Book yet: a placeholder Cover, its Title,
/// and its status.
struct ImportCard: View {
    let record: Import
    /// Pages done and total from the Library's latest event, if newer than `record`.
    let liveProgress: (done: Int, total: Int)?
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CoverPlaceholder()
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay { coverOverlay }
                .clipShape(.rect(cornerRadius: 6))
                .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                .padding(.bottom, 4)
            Text(record.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .contain)
    }

    private var pages: (done: Int, total: Int?) {
        if let liveProgress { return (liveProgress.done, liveProgress.total) }
        return (record.pagesDone, record.pagesTotal)
    }

    private var statusText: String {
        switch record.status {
        case .inProgress:
            if let total = pages.total {
                return String(localized: "\(pages.done) of \(total)")
            }
            return String(localized: "Preparing…")
        case .queued:
            return String(localized: "Waiting")
        case .failed:
            return record.failureReason?.localizedDescription ?? ""
        case .completed:
            return ""
        }
    }

    @ViewBuilder private var coverOverlay: some View {
        switch record.status {
        case .inProgress:
            if let total = pages.total, total > 0 {
                ProgressView(value: Double(pages.done), total: Double(total))
                    .progressViewStyle(.circular)
            } else {
                ProgressView()
            }
        case .queued:
            Image(systemName: "clock")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        case .failed:
            Button("Retry", systemImage: "arrow.clockwise", action: onRetry)
                .buttonStyle(.bordered)
                .controlSize(.small)
        case .completed:
            EmptyView()
        }
    }
}

extension ImportFailureReason {
    /// What the user is told when an Import Fails for this reason.
    var localizedDescription: String {
        switch self {
        case .noImagesFound: String(localized: "No images found")
        case .unreadableZip: String(localized: "This zip can't be read")
        case .unsupportedZip: String(localized: "This zip format isn't supported")
        case .sourceNotDownloaded: String(localized: "Not downloaded to this device")
        case .notEnoughStorage: String(localized: "Not enough storage")
        case .sourceUnavailable: String(localized: "The folder or zip is no longer available")
        case .cancelled: String(localized: "Cancelled")
        case .storageFailure: String(localized: "Couldn't write to Folio's storage")
        case .undecodablePage: String(localized: "The first page couldn't be read")
        }
    }
}
