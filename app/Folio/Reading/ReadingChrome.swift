import SwiftUI

/// The controls at the bottom of the open Book: the page counter and a slider over
/// every Page. The Title and Close live in the toolbar, which each platform draws.
struct ReadingChrome: View {
    /// The Page being read, 0-based.
    @Binding var index: Int
    let pageCount: Int

    var body: some View {
        VStack(spacing: 4) {
            Text("Page \(index + 1) of \(pageCount)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            Slider(value: sliderValue, in: 0...Double(max(pageCount - 1, 1)), step: 1) {
                Text("Page \(index + 1) of \(pageCount)")
            }
            // A Book of one Page has nowhere to jump to.
            .disabled(pageCount < 2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var sliderValue: Binding<Double> {
        Binding(
            get: { Double(index) },
            set: { index = Int($0.rounded()) }
        )
    }
}
