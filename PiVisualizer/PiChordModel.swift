import SwiftUI
import Observation

@MainActor
@Observable
final class PiChordModel {
    static let countOptions = [100, 1_000, 10_000, 100_000, 1_000_000]

    private(set) var digitCount = Stored.choice("chords.digits", among: PiChordModel.countOptions, default: 1_000)
    /// Chords drawn so far; the fractional part is how far the newest chord has grown.
    private(set) var position: Double = 0
    var isPlaying = false
    /// Chords per second while playing.
    var speed: Double = Stored.value("chords.speed", default: 20) { didSet { Stored.set(speed, "chords.speed") } }
    var hapticsOn: Bool = Stored.value("chords.haptics", default: true) { didSet { Stored.set(hapticsOn, "chords.haptics") } }

    /// Finished chords, one path per source digit (in unit-circle coordinates) so the
    /// canvas strokes 10 paths per frame instead of thousands of separate ones.
    private(set) var chordPaths = Array(repeating: Path(), count: 10)
    /// Chords handed to the background bake but not yet in `baked`; still drawn live meanwhile.
    private(set) var pendingPaths = Array(repeating: Path(), count: 10)
    private(set) var completed = 0

    /// Older chords rasterised into a bitmap covering the unit square [-1, 1]. In runs of 10,000
    /// digits or more, every `bakeThreshold` chords the vector paths are flattened into it so each
    /// frame re-strokes only a few hundred curves. Shorter runs stay fully vector.
    private(set) var baked = BakedImages()
    @ObservationIgnored private let layers = BakedLayers()
    /// Number of chords (from the start) handed to the baked layers.
    @ObservationIgnored private var bakedCount = 0
    /// One bake at a time; chords that arrive meanwhile wait for the next, larger batch.
    @ObservationIgnored private var bakeInFlight = false
    /// Chords in `pendingPaths`.
    @ObservationIgnored private var pendingCount = 0
    /// If baking falls this far behind, playback holds rather than piling up live curves,
    /// which the renderer re-flattens on the CPU every frame.
    private static let maxLiveChords = 4_000
    private static let bakeThreshold = 500

    /// Whose digits are drawn: π, or e, √2 or φ for comparison.
    private(set) var constant = Constant(rawValue: Stored.value("chords.constant", default: Constant.pi.rawValue)) ?? .pi
    /// The chosen number's digits; read in tight loops, so not observed (`constant` is).
    @ObservationIgnored private(set) var digits = PiDigits.all
    @ObservationIgnored private let haptics = DigitHaptics()

    var chordTotal: Int { digitCount - 1 }
    var isFinished: Bool { completed >= chordTotal }

    /// The chord currently being drawn and how much of it is visible.
    var liveChord: (path: Path, progress: Double)? {
        guard !isFinished else { return nil }
        let progress = position - Double(completed)
        guard progress > 0 else { return nil }
        return (chord(completed), progress)
    }

    /// Line width (points) and opacity that keep the diagram readable as it gets denser.
    var chordStyle: (width: CGFloat, opacity: Double) {
        switch digitCount {
        case ...100: (1.6, 0.85)
        case ...1_000: (0.9, 0.45)
        // Baked chords are stroked one by one, so overlaps add up; keep each one faint.
        case ...10_000: (0.5, 0.06)
        case ...100_000: (0.35, 0.012)
        // Float bitmaps keep strokes this faint from rounding away.
        default: (0.3, 0.0016)
        }
    }

    init() {
        digits = constant.digits
        // A remembered million-digit run needs the high-precision bitmaps from the start.
        restart()
    }

    func setConstant(_ newConstant: Constant) {
        constant = newConstant
        digits = newConstant.digits
        Stored.set(newConstant.rawValue, "chords.constant")
        restart()
    }

    func setDigitCount(_ count: Int) {
        digitCount = count
        Stored.set(count, "chords.digits")
        restart()
    }

    func restart() {
        position = 0
        completed = 0
        chordPaths = Array(repeating: Path(), count: 10)
        pendingPaths = Array(repeating: Path(), count: 10)
        pendingCount = 0
        layers.clear(highPrecision: digitCount > 100_000)
        baked = BakedImages()
        bakedCount = 0
        bakeInFlight = false
    }

    func togglePlay() {
        if isFinished { restart() }
        isPlaying.toggle()
    }

    func tick(seconds: Double) {
        guard isPlaying else { return }
        advance(to: position + speed * seconds)
    }

    /// Draws exactly one more chord; used for tap-to-step.
    func step() {
        advance(to: Double(completed + 1))
    }

    private func advance(to target: Double) {
        if digitCount >= 10_000, pendingCount + completed - bakedCount >= Self.maxLiveChords { return }
        position = min(target, Double(chordTotal))
        let reached = Int(position)
        guard reached > completed else { return }
        for i in completed..<reached {
            chordPaths[Int(digits[i])].addPath(chord(i))
        }
        completed = reached
        if digitCount >= 10_000, !bakeInFlight, completed - bakedCount >= Self.bakeThreshold { bake() }
        if hapticsOn { haptics.play(digit: digits[reached]) }
        PiMusic.shared.play(digit: digits[reached])
        if isFinished { PiMusic.shared.playChord() }
        if isFinished { isPlaying = false }
    }

    /// Re-renders the baked chords sharply for a settled pinch zoom.
    func zoomSettled(_ zoom: CGFloat) {
        layers.setDetailZoom(zoom, redraw: strokes(for: 0..<bakedCount)) { [weak self] in self?.baked = $0 }
    }

    private func bake() {
        let strokes = strokes(for: bakedCount..<completed)
        pendingPaths = chordPaths
        pendingCount = completed - bakedCount
        chordPaths = Array(repeating: Path(), count: 10)
        bakedCount = completed
        bakeInFlight = true
        layers.draw(strokes) { [weak self] images in
            guard let self else { return }
            baked = images
            pendingPaths = Array(repeating: Path(), count: 10)
            pendingCount = 0
            bakeInFlight = false
        }
    }

    /// Strokes for a range of chords, safe to run off the main thread.
    private func strokes(for range: Range<Int>) -> BakedLayers.Strokes {
        let digits = digits
        let span = Double(chordTotal)
        let style = chordStyle
        let colors = (0..<10).map { UIColor(ChordLayout.color($0).opacity(style.opacity)).cgColor }
        return { context, point in
            context.setLineWidth(style.width * point)
            // Butt caps: round ones would overlap where pieces meet and leave brighter dots.
            context.setLineCap(.butt)
            // Stroke chords one at a time: stroking a digit's combined path makes Core Graphics
            // resolve every crossing between its curves, which stalls for thousands of chords.
            for i in range {
                context.setStrokeColor(colors[Int(digits[i])])
                for piece in ChordLayout.chordPieces(from: Int(digits[i]), at: Double(i) / span,
                                                     to: Int(digits[i + 1]), at: Double(i + 1) / span, count: 4) {
                    context.addPath(piece)
                    context.strokePath()
                }
            }
        }
    }

    private func chord(_ i: Int) -> Path {
        let span = Double(chordTotal)
        return ChordLayout.chord(from: Int(digits[i]), at: Double(i) / span,
                                 to: Int(digits[i + 1]), at: Double(i + 1) / span)
    }
}
