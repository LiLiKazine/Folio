import CoreGraphics
import SwiftUI

/// One Page of the open Book, fitted to its frame, with pinch and double-tap zoom.
/// A Page that cannot be decoded shows a placeholder in its place.
struct PageView: View {
    /// The Page's place in the Book, 0-based.
    let index: Int
    let pageCount: Int
    /// Nil until the window's size is known; the Page shows nothing until then.
    let cache: PageImageCache?
    /// A single tap on the Page, which shows or hides the chrome.
    let onTap: () -> Void

    /// What decoding the Page produced.
    private enum Loaded {
        case loading
        case image(CGImage)
        case unavailable
    }

    /// The scale a double tap zooms to; a second double tap returns to fit.
    static let zoomedScale: CGFloat = 2.5
    private static let maximumScale: CGFloat = 5

    @State private var loaded = Loaded.loading
    /// The scale the Page rests at; 1 is fit to the frame.
    @State private var scale: CGFloat = 1
    /// The scale while a pinch is in progress, relative to `scale`.
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        GeometryReader { frame in
            ScrollView([.horizontal, .vertical]) {
                content
                    .frame(
                        width: frame.size.width * liveScale, height: frame.size.height * liveScale)
            }
            .scrollIndicators(.hidden)
            // Zoom grows the Page about its centre, not its top-left corner.
            .defaultScrollAnchor(.center)
            .defaultScrollAnchor(.center, for: .sizeChanges)
            // A Page at fit has nothing to pan, so the Book's paging gets every drag.
            .scrollDisabled(scale <= 1)
            .contentShape(.rect)
            .gesture(
                TapGesture(count: 2).onEnded { toggleZoom() }
                    .exclusively(before: TapGesture().onEnded { onTap() })
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in
                        scale = min(max(scale * value.magnification, 1), Self.maximumScale)
                    }
            )
        }
        .task(id: cache.map(ObjectIdentifier.init)) {
            guard let cache else { return }
            let image = await cache.image(at: index)
            // Cancelled means this Page left the screen: nil is no verdict on the file.
            guard !Task.isCancelled else { return }
            loaded = image.map(Loaded.image) ?? .unavailable
        }
    }

    private var liveScale: CGFloat {
        min(max(scale * pinch, 1), Self.maximumScale)
    }

    @ViewBuilder private var content: some View {
        switch loaded {
        case .loading:
            Color.clear
        case .image(let image):
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .accessibilityLabel(Text("Page \(index + 1) of \(pageCount)"))
                .accessibilityAddTraits(.isImage)
        case .unavailable:
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("Page \(index + 1) could not be shown"))
        }
    }

    private func toggleZoom() {
        withAnimation {
            scale = scale > 1 ? 1 : Self.zoomedScale
        }
    }
}
