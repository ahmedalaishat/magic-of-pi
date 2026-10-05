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

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(onOpen: { path = [$0] }, onFindBirthday: { find.isOpen = true })
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

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
