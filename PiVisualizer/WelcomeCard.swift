import SwiftUI

/// Shown once, after the splash on first launch: where everything is.
struct WelcomeCard: View {
    let onDone: () -> Void

    private let tips: [(icon: String, text: String)] = [
        ("square.grid.2x2", "Pick a visualization on the home screen, or let \"Show me the magic\" play the best moments."),
        ("play.circle.fill", "Play and pause anytime. In Chords, tap the circle to draw one digit at a time."),
        ("slider.horizontal.3", "Options: digits, speed, sound, and Find your birthday in π."),
        ("video", "Camera moves in the 3D modes."),
        ("scope", "Rods with Spotlight zoom into π's near-misses: 22/7 and 355/113."),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                Text("Welcome to Magic of π")
                    .font(.title2.bold())
                ForEach(tips, id: \.text) { tip in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: tip.icon)
                            .font(.title3)
                            .foregroundStyle(.purple)
                            .frame(width: 28)
                        Text(tip.text)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button(action: onDone) {
                    Text("Start exploring").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .controlSize(.large)
                .padding(.top, 4)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .padding(20)
        }
    }
}
