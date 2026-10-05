import Observation
import SwiftUI

/// "Show me the magic": a guided tour through the best moments, one mode after another.
@MainActor
@Observable
final class Showcase {
    static let shared = Showcase()

    /// Set by the options sheet; the content view starts the tour and clears it.
    var requested = false
    /// The caption of the step playing, or nil when no tour is running.
    var caption: String?
}

/// The tour's caption, over the bottom controls (which the tour drives itself).
struct ShowcaseCaption: View {
    let text: String
    let onEnd: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(text)
                .font(.callout)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .animation(.easeInOut, value: text)
            HStack(spacing: 16) {
                RecordButton()
                Button("End tour", action: onEnd)
                    .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 16)
    }
}
