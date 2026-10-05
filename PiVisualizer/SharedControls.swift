import SwiftUI

/// Calls `tick` with the elapsed seconds about once per frame while `isRunning` stays true.
@MainActor
func runFrameLoop(while isRunning: () -> Bool, tick: (Double) -> Void) async {
    let clock = ContinuousClock()
    var last = clock.now
    while isRunning(), !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(16))
        let now = clock.now
        let elapsed = (now - last).components
        tick(Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
        last = now
    }
}

/// Speed slider on a logarithmic scale between `range` bounds.
struct SpeedSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        let ratio = range.upperBound / range.lowerBound
        HStack {
            Image(systemName: "tortoise.fill").foregroundStyle(.secondary)
            Slider(value: Binding(get: { log(value / range.lowerBound) / log(ratio) },
                                  set: { value = range.lowerBound * pow(ratio, $0) }))
            Image(systemName: "hare.fill").foregroundStyle(.secondary)
        }
    }
}

/// The only controls kept on screen: restart, play/pause, options, and camera moves in 3D.
struct ControlBar: View {
    let isPlaying: Bool
    let onRestart: () -> Void
    let onTogglePlay: () -> Void
    let onOptions: () -> Void
    var shots: [CameraShot] = []
    var onShot: (CameraShot) -> Void = { _ in }

    var body: some View {
        HStack {
            HStack(spacing: 24) {
                Button(action: onRestart) { Image(systemName: "arrow.counterclockwise") }
                    .accessibilityLabel("Restart")
                if !shots.isEmpty { CameraMenu(shots: shots, onShot: onShot) }
                RecordButton()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onTogglePlay) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 58))
            }
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            Button(action: onOptions) { Image(systemName: "slider.horizontal.3") }
                .accessibilityLabel("Options")
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.title2)
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
    }
}

/// Scripted camera moves, behind one button.
struct CameraMenu: View {
    let shots: [CameraShot]
    let onShot: (CameraShot) -> Void

    var body: some View {
        Menu {
            ForEach(shots) { shot in
                Button { onShot(shot) } label: { Label(shot.rawValue, systemImage: shot.icon) }
            }
        } label: {
            Image(systemName: "video")
        }
        .accessibilityLabel("Camera moves")
    }
}

/// Settings for a mode, in a half-height sheet that leaves the visualization visible and live
/// above it. Each mode adds its own sections; playback and explore sections are shared.
struct OptionsSheet<ModeOptions: View>: View {
    let topic: ModeTopic
    @Binding var speed: Double
    let speedRange: ClosedRange<Double>
    @Binding var hapticsOn: Bool
    /// Renders the current visualization as a wallpaper.
    let makeWallpaper: () -> Void
    @ViewBuilder let modeOptions: () -> ModeOptions
    @Environment(\.dismiss) private var dismiss
    @State private var showingInfo = false

    var body: some View {
        NavigationStack {
            Form {
                modeOptions()
                Section("Playback") {
                    SpeedSlider(value: $speed, range: speedRange)
                    Toggle(isOn: $hapticsOn) { Label("Haptics", systemImage: "iphone.radiowaves.left.and.right") }
                    Toggle(isOn: Binding(get: { PiMusic.shared.isOn }, set: { PiMusic.shared.isOn = $0 })) {
                        Label("Sound", systemImage: "speaker.wave.2")
                    }
                }
                .tint(.purple)
                Section("Share") {
                    Button {
                        dismiss()
                        // Render after the sheet is gone, so the 3D snapshot isn't covered.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: makeWallpaper)
                    } label: {
                        Label("Save as wallpaper", systemImage: "photo")
                    }
                }
                Section("Explore") {
                    Button { showingInfo = true } label: { Label(topic.title, systemImage: "info.circle") }
                }
            }
            .navigationTitle("Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.fraction(0.45), .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.45)))
        .sheet(isPresented: $showingInfo) {
            InfoSheet(topic: topic).presentationDetents([.medium, .large])
        }
    }
}

/// Pinch to zoom (1×–8×), double-tap to reset, and an optional single tap. The content draws
/// itself at the zoom it is handed instead of being scaled up as an image, so it stays sharp.
struct ZoomableView<Content: View>: View {
    var onTap: (() -> Void)?
    /// Called when a pinch ends or the zoom resets, so baked history can re-render at the new zoom.
    let onZoomSettled: (CGFloat) -> Void
    @ViewBuilder let content: (CGFloat) -> Content
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        content(Self.clamp(zoom * pinch))
            .contentShape(Rectangle())
            .gesture(MagnifyGesture()
                .updating($pinch) { value, state, _ in state = value.magnification }
                .onEnded { value in
                    zoom = Self.clamp(zoom * value.magnification)
                    onZoomSettled(zoom)
                })
            .onTapGesture(count: 2) {
                zoom = 1
                onZoomSettled(1)
            }
            .onTapGesture { onTap?() }
            .clipped()
    }

    private static func clamp(_ zoom: CGFloat) -> CGFloat { min(max(zoom, 1), 8) }
}

/// Opens the "Find in π" search; shared through the environment.
@Observable
final class FindInPi {
    var isOpen = false
}

/// A small counter in the corner of the visualization. Evaluated in its own body, so a value that
/// changes every frame only redraws the badge.
struct CounterBadge: View {
    let text: () -> String

    var body: some View {
        // Hidden while recording, so clips show only the visualization.
        Text(VideoRecorder.shared.isRecording ? "" : text())
            .opacity(VideoRecorder.shared.isRecording ? 0 : 1)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.black.opacity(0.45), in: Capsule())
            .padding(10)
            .allowsHitTesting(false)
    }
}

extension View {
    /// The context line under a visualization, set in a soft full-width card.
    func infoCard() -> some View {
        frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Starts and stops a recording of the visualization; shows the elapsed time while recording.
struct RecordButton: View {
    private let recorder = VideoRecorder.shared

    var body: some View {
        Button(action: recorder.toggle) {
            if recorder.isRecording {
                HStack(spacing: 4) {
                    Image(systemName: "stop.circle.fill").foregroundStyle(.red)
                    RecordingIndicator()
                }
            } else {
                Image(systemName: "record.circle")
            }
        }
        .disabled(recorder.state == .finishing)
        .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Record a clip")
    }
}
