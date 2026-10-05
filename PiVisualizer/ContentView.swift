import SwiftUI

struct ContentView: View {
    enum Mode: String, CaseIterable, Hashable {
        case chords = "Chords"
        case rods = "Rods"
        case walk = "3D Walk"
        case spring = "3D Spring"
    }

    /// The home screen, then the open visualization (at most one).
    @State private var path: [Mode] = []
    @State private var chords = PiChordModel()
    @State private var rods = RodsModel()
    @State private var walk = WalkModel()
    @State private var spring = SpringModel()
    @State private var find = FindInPi()
    @AppStorage("seenWelcome") private var seenWelcome = false
    @Bindable private var recorder = VideoRecorder.shared
    @Bindable private var wallpaper = Wallpaper.shared
    private let showcase = Showcase.shared
    @State private var tour: Task<Void, Never>?

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(onOpen: { path = [$0] }, onTour: startTour, onFindBirthday: { find.isOpen = true })
                .navigationDestination(for: Mode.self) { mode in
                    Group {
                        switch mode {
                        case .chords: ChordModeView(model: chords)
                        case .rods: RodsModeView(model: rods)
                        case .walk: WalkModeView(model: walk)
                        case .spring: SpringModeView(model: spring)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(Color.black.ignoresSafeArea())
                    .navigationTitle(mode.rawValue)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(.black, for: .navigationBar)
                }
        }
        .tint(.white)
        .environment(find)
        .overlay(alignment: .bottom) {
            if let caption = showcase.caption {
                ShowcaseCaption(text: caption, onEnd: endTour)
                    .padding(.bottom, 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: showcase.requested) { _, requested in
            if requested {
                showcase.requested = false
                startTour()
            }
        }
        .overlay {
            if !seenWelcome {
                WelcomeCard { withAnimation { seenWelcome = true } }
                    .transition(.opacity)
            }
        }
        .sheet(item: $recorder.finishedClip) { ClipPreview(url: $0) }
        .sheet(item: $wallpaper.rendered) { WallpaperPreview(image: $0.image) }
        .alert("Recording failed", isPresented: Binding(get: { recorder.failure != nil },
                                                         set: { if !$0 { recorder.failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(recorder.failure ?? "")
        }
        .sheet(isPresented: $find.isOpen) {
            FindInPiView { steps in
                path = [.walk]
                walk.jump(to: steps)
            }
        }
        // Only the visible mode animates; the others keep their drawings but stop.
        .onChange(of: path) {
            chords.isPlaying = false
            rods.isPlaying = false
            walk.isPlaying = false
            spring.isPlaying = false
        }
    }
}

// MARK: - Tour

extension ContentView {
    private struct TourStep {
        let caption: String
        let seconds: Double
        let start: @MainActor () -> Void
    }

    private func startTour() {
        tour?.cancel()
        tour = Task { await runTour() }
    }

    private func endTour() {
        tour?.cancel()
        tour = nil
        stopAll()
        withAnimation { showcase.caption = nil }
    }

    private func stopAll() {
        chords.isPlaying = false
        rods.isPlaying = false
        walk.isPlaying = false
        spring.isPlaying = false
    }

    private func runTour() async {
        let steps: [(Mode, TourStep)] = [
            (.chords, TourStep(caption: "π's digits go 3, 1, 4, 1, 5, 9… Each neighbouring pair draws a chord between its two digits. No pair is favoured: the circle fills evenly.",
                               seconds: 9) {
                chords.setDigitCount(10_000)
                chords.speed = 1_500
                chords.isPlaying = true
            }),
            (.rods, TourStep(caption: "Two rods, one spinning π times faster. Because π is no fraction, the pen never returns to its start, but after 7 turns it comes very close: π ≈ 22/7.",
                             seconds: 22) {
                rods.setStyle(.classic)
                rods.spotlightOn = true
                rods.speed = 3
                rods.isPlaying = true
            }),
            (.walk, TourStep(caption: "Each digit is one step in its own 3D direction. 100,000 digits of π wander like a random walk.",
                             seconds: 14) {
                walk.setDigitCount(100_000)
                walk.speed = 8_000
                walk.isPlaying = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) { walk.play(.flythrough) }
            }),
            (.spring, TourStep(caption: "Stack the rods' turns into a spring. From above, turn 113's loop lands almost exactly on turn 0's: π ≈ 355/113, right to six decimals.",
                               seconds: 17) {
                spring.setTurnCount(120)
                spring.speed = 12
                spring.isPlaying = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 9.5) { spring.play(.topDown) }
            }),
        ]
        for (stepMode, step) in steps {
            guard !Task.isCancelled else { return }
            withAnimation { showcase.caption = step.caption }
            path = [stepMode]
            // Let the tab switch (which pauses everything) settle before starting the step.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            step.start()
            try? await Task.sleep(for: .seconds(step.seconds))
        }
        guard !Task.isCancelled else { return }
        withAnimation { showcase.caption = "That's the magic of π: endless, never repeating, and never quite closing." }
        try? await Task.sleep(for: .seconds(4))
        guard !Task.isCancelled else { return }
        path = []
        endTour()
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
