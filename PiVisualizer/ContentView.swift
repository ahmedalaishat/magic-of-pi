import SwiftUI

struct ContentView: View {
    enum Mode: String, CaseIterable {
        case chords = "Chords"
        case rods = "Rods"
        case walk = "3D Walk"
        case spring = "3D Spring"
    }

    @AppStorage("mode") private var mode = Mode.chords
    @State private var chords = PiChordModel()
    @State private var rods = RodsModel()
    @State private var walk = WalkModel()
    @State private var spring = SpringModel()
    @State private var find = FindInPi()

    var body: some View {
        VStack(spacing: 8) {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            switch mode {
            case .chords: ChordModeView(model: chords)
            case .rods: RodsModeView(model: rods)
            case .walk: WalkModeView(model: walk)
            case .spring: SpringModeView(model: spring)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.black.ignoresSafeArea())
        .environment(find)
        .sheet(isPresented: $find.isOpen) {
            FindInPiView { steps in
                mode = .walk
                walk.jump(to: steps)
            }
        }
        // Only the visible mode animates; the other keeps its drawing but stops.
        .onChange(of: mode) {
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
