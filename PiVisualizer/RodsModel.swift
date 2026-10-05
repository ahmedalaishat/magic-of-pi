import SwiftUI
import Observation

/// A chain of rods joined end to end, each spinning at its own speed; a pen on the last rod's tip
/// draws the trail. θ is the angle of a speed-1 rod, and rod k sits at speed_k·θ + phase_k.
@MainActor
@Observable
final class RodsModel {
    enum Style: String, CaseIterable {
        /// Two equal rods at speeds 1 and π. The trail never closes because π is irrational;
        /// it comes closest after 7, 106 and 113 turns, where π ≈ 22/7, 333/106 and 355/113.
        case classic = "1 : π"
        /// Rod k spins at the speed of π's k-th digit, alternating direction. Whole-number speeds
        /// make the trail close into a flower after one turn.
        case digits = "π's digits"
        /// The largest Fourier circles of a "π" glyph's outline; more rods draw it more sharply.
        case drawPi = "Draw π"
        /// Rods the viewer edits, written as z(θ) = Σ length·e^{(speed·θ)i}.
        case formula = "Formula"
    }

    struct Rod { let length: Double, speed: Double, phase: Double }

    /// An editable rod: its speed is `multiplier`, times π when `timesPi` is set.
    struct FormulaRod: Identifiable, Equatable {
        let id = UUID()
        var length: Double
        var multiplier: Double
        var timesPi: Bool
        var speed: Double { timesPi ? multiplier * .pi : multiplier }
    }

    /// z(θ) = e^{θi} + .9e^{(−πθ)i} + .8e^{(2πθ)i}
    static let formulaPreset = [FormulaRod(length: 1, multiplier: 1, timesPi: false),
                                FormulaRod(length: 0.9, multiplier: -1, timesPi: true),
                                FormulaRod(length: 0.8, multiplier: 2, timesPi: true)]
    static let maxFormulaRods = 6
    struct Fraction { let turns: Int, numerator: Int }
    static let convergents = [Fraction(turns: 7, numerator: 22),
                              Fraction(turns: 106, numerator: 333),
                              Fraction(turns: 113, numerator: 355)]

    private(set) var style = Style.classic
    private(set) var rodCount = 2
    private(set) var rods: [Rod] = RodsModel.makeRods(.classic, count: 2, formula: [])
    /// Editing the formula restarts the drawing with the new rods.
    var formulaRods = RodsModel.formulaPreset {
        didSet { if style == .formula, formulaRods != oldValue { rebuild() } }
    }
    /// Angle of a speed-1 rod, in radians.
    private(set) var theta: Double = 0
    var isPlaying = false
    /// Turns per second of a speed-1 rod.
    var speed: Double = 0.5
    var hapticsOn = true
    /// Slow down and zoom in on the start point around each near-miss turn.
    var spotlightOn = false

    /// Where the view looks: `zoom` around `center`, in unit coordinates.
    struct Camera {
        var zoom: CGFloat = 1
        var center = CGPoint.zero
        /// The near-miss turn being spotlighted, if any.
        var turn: Int?
    }

    /// Turns where the pen passes closer to its start than on any earlier turn (and close enough to
    /// matter): 7, 106 and 113 for speeds 1 and π. Only for trails that never close.
    @ObservationIgnored private(set) var nearMisses: [Int] = []
    /// For each whole turn, the moment nearby when the pen passes closest to its start, and how close.
    /// The pen returns along almost the same track, so this sideways miss is ~300× smaller than the
    /// distance at the exact turn: 0.00009 after 7 turns, 0.000000001 after 113.
    @ObservationIgnored private var approaches: [(theta: Double, distance: Double)] = []
    private static let gapScanTurns = 2_000
    /// On-screen pen speed, in points per second, while the spotlight is zoomed in.
    private static let spotlightScreenSpeed = 180.0
    /// Playback speed, in turns per second, during the turn before a near-miss.
    private static let spotlightCalmSpeed = 0.15
    /// Turn 113 misses by about 1e-9, which needs roughly ×2,000,000,000 to show as two lines.
    private static let maxSpotlightZoom = 10_000_000_000.0

    /// Trail points not yet baked; point k is sample `liveStartIndex + k`.
    private(set) var livePoints: [CGPoint] = []
    @ObservationIgnored private var liveStartIndex = 0
    private(set) var baked = BakedImages()
    /// Trail handed to the background bake but not yet in `baked`; still drawn live meanwhile.
    private(set) var pendingChunks: [(path: Path, color: Color)] = []
    @ObservationIgnored private let layers = BakedLayers()
    /// One bake at a time; trail that arrives meanwhile waits for the next, larger batch.
    @ObservationIgnored private var bakeInFlight = false
    /// Every baked trail point, from sample 0 up to `liveStartIndex`, kept to re-render on zoom.
    @ObservationIgnored private var history: [CGPoint] = []
    @ObservationIgnored private let haptics = DigitHaptics()

    /// Points per coloured stroke; the trail's hue drifts, so it is drawn in short runs.
    private static let chunkSize = 64
    private static let bakeThreshold = 1_200
    static let trailWidth: CGFloat = 1.1

    init() {
        livePoints = [pen(at: 0)]
        findNearMisses()
    }

    var rodCountRange: ClosedRange<Int>? {
        switch style {
        case .classic: nil
        case .digits: 2...20
        case .drawPi: 1...200
        case .formula: nil
        }
    }

    var turns: Double { theta / (2 * .pi) }
    /// Whole-number speeds bring every rod home after exactly one turn, closing the curve.
    var closesAfterOneTurn: Bool {
        switch style {
        case .classic: false
        case .digits, .drawPi: true
        case .formula: formulaRods.allSatisfy { !$0.timesPi && $0.multiplier == $0.multiplier.rounded() }
        }
    }
    var isFinished: Bool { closesAfterOneTurn && turns >= 1 }

    var trailOpacity: Double {
        switch style {
        case .classic: 0.55
        case .formula: 0.7
        case .digits, .drawPi: 0.9
        }
    }

    /// The best fraction for π reached so far (classic style only).
    var latestConvergent: Fraction? {
        guard style == .classic else { return nil }
        return Self.convergents.last { Double($0.turns) <= turns + 1e-9 }
    }

    /// Distance from the pen to where it started, as a share of the full reach.
    var gap: Double {
        let p = pen(at: theta), start = pen(at: 0)
        return hypot(p.x - start.x, p.y - start.y) / rods.reduce(0) { $0 + $1.length } / 2
    }

    /// The origin followed by the end of each rod, in unit-circle coordinates (y down).
    func joints(at theta: Double) -> [CGPoint] {
        var x = 0.0, y = 0.0
        var points = [CGPoint.zero]
        for rod in rods {
            let angle = rod.speed * theta + rod.phase
            x += rod.length * cos(angle)
            y -= rod.length * sin(angle)
            points.append(CGPoint(x: x, y: y))
        }
        return points
    }

    func pen(at theta: Double) -> CGPoint {
        var x = 0.0, y = 0.0
        for rod in rods {
            let angle = rod.speed * theta + rod.phase
            x += rod.length * cos(angle)
            y -= rod.length * sin(angle)
        }
        return CGPoint(x: x, y: y)
    }

    /// Hue cycles once per closed curve, or every 7 turns for the classic style so the
    /// near-closure at 22/7 lands back on its starting colour.
    func color(at theta: Double) -> Color {
        if style == .formula { return Color(hue: 0.74, saturation: 0.8, brightness: 1) }
        let cycle = style == .classic ? 7.0 : 1.0
        return Color(hue: (theta / (2 * .pi) / cycle).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 1)
    }

    /// The unbaked trail split into short paths, each with its own colour.
    func liveChunks() -> [(path: Path, color: Color)] {
        chunks(of: livePoints, startIndex: liveStartIndex)
    }

    /// Re-renders the baked trail sharply for a settled pinch zoom.
    func zoomSettled(_ zoom: CGFloat) {
        let strokes = strokes(for: chunks(of: history + livePoints.prefix(1), startIndex: 0))
        layers.setDetailZoom(zoom, redraw: strokes) { [weak self] in self?.baked = $0 }
    }

    var camera: Camera { camera(at: theta) }

    /// The next near-miss turn not yet passed, or nil if there is none within the scan.
    var upcomingNearMiss: Int? {
        nearMisses.first { 2 * .pi * Double($0) + .pi > theta }
    }

    /// Within two turns of a near-miss, the camera frames the pen and its start, zooming in as they
    /// close so the gap stays visible, then back out as the pen moves away.
    func camera(at theta: Double) -> Camera {
        guard spotlightOn, let (n, weight) = spotlightWindow(at: theta) else { return Camera() }
        let start = pen(at: 0), p = pen(at: theta)
        // Frame tighter as the pen closes in; at the closest point the gap spans about two-thirds of the view.
        let distance = max(hypot(p.x - start.x, p.y - start.y), approaches[n].distance * 0.35)
        let target = min(max(0.6 / distance, 1), Self.maxSpotlightZoom)
        // Ease in log space so zooming feels even from 1× to 1000×.
        let zoom = pow(target, weight)
        // Pan from the whole drawing onto the pen and its start by ×3, then stay locked on them.
        // (Easing the pan with 1 - 1/zoom leaves an offset as wide as the view at high zoom.)
        let t = min(log(zoom) / log(3), 1)
        let pan = t * t * (3 - 2 * t)
        return Camera(zoom: zoom,
                      center: CGPoint(x: (p.x + start.x) / 2 * pan, y: (p.y + start.y) / 2 * pan),
                      turn: n)
    }

    /// The trail near the start point, sampled finely enough for the spotlight's zoom; the baked and
    /// live trail are far too coarse at hundreds of times magnification. Points stay in double
    /// precision (unit coordinates) for the caller to map to screen. Empty unless zoomed in.
    func spotlightPasses(_ camera: Camera) -> [(points: [CGPoint], color: Color)] {
        guard camera.zoom > 3, let n = camera.turn, n < approaches.count else { return [] }
        let halfWidth = 1.2 / camera.zoom
        var passes: [(points: [CGPoint], color: Color)] = []
        for m in 0...n where m == n || approaches[m].distance < 3 * halfWidth {
            let middle = approaches[m].theta
            let v = velocity(at: middle)
            let reach = min(.pi, (2.5 * halfWidth + approaches[m].distance) / max(hypot(v.x, v.y), 0.01))
            let low = m == 0 ? 0 : middle - reach
            let high = m == n ? min(middle + reach, theta) : middle + reach
            guard high > low else { continue }
            passes.append(((0...240).map { pen(at: low + (high - low) * Double($0) / 240) }, color(at: middle)))
        }
        return passes
    }

    /// Where the pen is about to go, from now to past the edge of the spotlight's view, in unit
    /// coordinates (double precision). Empty unless the spotlight is zoomed in.
    func spotlightPreview(_ camera: Camera) -> [CGPoint] {
        guard camera.zoom > 1.5, camera.turn != nil else { return [] }
        let v = velocity(at: theta)
        let ahead = min(.pi, 3 * 1.2 / camera.zoom / max(hypot(v.x, v.y), 0.01))
        return (0...160).map { pen(at: theta + ahead * Double($0) / 160) }
    }

    func setStyle(_ newStyle: Style) {
        style = newStyle
        rodCount = switch newStyle {
        case .classic: 2
        case .digits: 6
        case .drawPi: 20
        case .formula: formulaRods.count
        }
        speed = switch newStyle {
        case .classic: 0.5
        case .formula: 0.25
        case .digits, .drawPi: 0.08
        }
        rebuild()
    }

    func setRodCount(_ count: Int) {
        guard count != rodCount else { return }
        rodCount = count
        rebuild()
    }

    func restart() {
        theta = 0
        livePoints = [pen(at: 0)]
        liveStartIndex = 0
        history = []
        pendingChunks = []
        layers.clear()
        baked = BakedImages()
        bakeInFlight = false
    }

    func togglePlay() {
        if isFinished { restart() }
        isPlaying.toggle()
    }

    func tick(seconds: Double) {
        guard isPlaying else { return }
        var target = theta + spotlightRate(at: theta) * seconds
        if closesAfterOneTurn { target = min(target, 2 * .pi) }

        // Collect new points locally and append once: each append to the observed array is tracked.
        var next = liveStartIndex + livePoints.count
        var added: [CGPoint] = []
        while Double(next) * sampleStep <= target + 1e-9 {
            added.append(pen(at: Double(next) * sampleStep))
            next += 1
        }
        if !added.isEmpty { livePoints.append(contentsOf: added) }

        let before = Int(turns)
        theta = target
        if !bakeInFlight, livePoints.count >= Self.bakeThreshold { bake() }

        if isFinished {
            isPlaying = false
            if hapticsOn { haptics.tap(intensity: 1, sharpness: 0.6) }
            PiMusic.shared.playChord()
        } else if !closesAfterOneTurn, Int(turns) > before {
            let closes = nearMisses.contains(Int(turns))
            if hapticsOn { haptics.tap(intensity: closes ? 1 : 0.45, sharpness: closes ? 0.9 : 0.3) }
            // Turn n plays π's n-th digit; a close call plays a chord.
            if closes {
                PiMusic.shared.playChord()
            } else {
                PiMusic.shared.play(digit: PiDigits.all[Int(turns) % PiDigits.all.count])
            }
        }
    }

    /// Angle between trail samples; finer when fast rods would otherwise make the trail jagged.
    /// Stored, and recomputed only when the rods change: it is read for every trail point.
    @ObservationIgnored private var sampleStep = 2 * Double.pi / 628

    private func computeSampleStep() -> Double {
        let samplesPerTurn = switch style {
        case .classic: 628
        case .digits: 1_024
        case .drawPi: 4_096
        // About 200 samples per turn of the fastest rod.
        case .formula: max(628, Int((formulaRods.map { abs($0.speed) }.max() ?? 1) * 200))
        }
        return 2 * .pi / Double(samplesPerTurn)
    }

    private func rebuild() {
        rodCount = style == .formula ? formulaRods.count : rodCount
        rods = Self.makeRods(style, count: rodCount, formula: formulaRods)
        sampleStep = computeSampleStep()
        findNearMisses()
        restart()
    }

    private func findNearMisses() {
        nearMisses = []
        approaches = []
        guard !closesAfterOneTurn else { return }
        let start = pen(at: 0)
        var best = Double.infinity
        approaches.append((0, 0))
        for m in 1...Self.gapScanTurns {
            let approach = closestApproach(turn: m, start: start)
            approaches.append(approach)
            if approach.distance < best {
                best = approach.distance
                if approach.distance < 0.01 { nearMisses.append(m) }
            }
        }
    }

    /// The moment within a third of a radian of turn m when the pen passes closest to its start.
    private func closestApproach(turn m: Int, start: CGPoint) -> (theta: Double, distance: Double) {
        func distance(_ t: Double) -> Double {
            let p = pen(at: t)
            return hypot(p.x - start.x, p.y - start.y)
        }
        let middle = 2 * .pi * Double(m)
        var bestT = middle, bestD = distance(middle)
        for k in -30...30 {
            let t = middle + Double(k) * 0.01
            let d = distance(t)
            if d < bestD { (bestT, bestD) = (t, d) }
        }
        // Only refine passes that come anywhere near; the rest can't be near-misses.
        guard bestD < 0.05 else { return (bestT, bestD) }
        var low = bestT - 0.01, high = bestT + 0.01
        let ratio = (sqrt(5) - 1) / 2
        for _ in 0..<60 {
            let a = high - ratio * (high - low), b = low + ratio * (high - low)
            if distance(a) < distance(b) { high = b } else { low = a }
        }
        let t = (low + high) / 2
        return (t, distance(t))
    }

    /// The near-miss turn whose two-turn window contains θ, and how deep into it θ is
    /// (0 at the window's edge, 1 within the last half turn either side).
    private func spotlightWindow(at theta: Double) -> (turn: Int, weight: Double)? {
        guard let n = nearMisses.first(where: { abs(theta - 2 * .pi * Double($0)) < 2 * .pi }) else { return nil }
        let distance = abs(theta - 2 * .pi * Double(n))
        let t = min(max((2 * .pi - distance) / .pi, 0), 1)
        return (n, t * t * (3 - 2 * t))
    }

    /// Angular speed in radians per second: the chosen speed, eased down near a near-miss and capped
    /// while zoomed so the pen crosses the screen at a watchable pace.
    private func spotlightRate(at theta: Double) -> Double {
        var rate = speed * 2 * .pi
        guard spotlightOn, let (_, weight) = spotlightWindow(at: theta) else { return rate }
        rate += (min(rate, Self.spotlightCalmSpeed * 2 * .pi) - rate) * weight
        let zoom = camera(at: theta).zoom
        if zoom > 1 {
            let v = velocity(at: theta)
            let screenSpeed = max(hypot(v.x, v.y), 0.01) * BakedLayer.nominalRadius * zoom
            rate = min(rate, Self.spotlightScreenSpeed / screenSpeed)
        }
        return rate
    }

    /// dpen/dθ, in unit coordinates per radian.
    private func velocity(at theta: Double) -> CGPoint {
        var x = 0.0, y = 0.0
        for rod in rods {
            let angle = rod.speed * theta + rod.phase
            x -= rod.length * rod.speed * sin(angle)
            y -= rod.length * rod.speed * cos(angle)
        }
        return CGPoint(x: x, y: y)
    }

    private func bake() {
        let chunks = liveChunks()
        pendingChunks = chunks
        bakeInFlight = true
        layers.draw(strokes(for: chunks)) { [weak self] images in
            guard let self else { return }
            baked = images
            pendingChunks = []
            bakeInFlight = false
        }
        // Keep the last point so the live trail continues seamlessly from the baked one.
        history.append(contentsOf: livePoints.dropLast())
        liveStartIndex += livePoints.count - 1
        livePoints = [livePoints[livePoints.count - 1]]
    }

    /// Strokes for trail chunks, safe to run off the main thread.
    private func strokes(for chunks: [(path: Path, color: Color)]) -> BakedLayers.Strokes {
        let opacity = trailOpacity
        let width = Self.trailWidth
        let items = chunks.map { ($0.path.cgPath, UIColor($0.color.opacity(opacity)).cgColor) }
        return { context, point in
            context.setLineWidth(width * point)
            context.setLineCap(.round)
            for (path, color) in items {
                context.addPath(path)
                context.setStrokeColor(color)
                context.strokePath()
            }
        }
    }

    /// Splits trail points (the first being sample `startIndex`) into short paths, each with its own colour.
    private func chunks(of points: [CGPoint], startIndex: Int) -> [(path: Path, color: Color)] {
        guard points.count > 1 else { return [] }
        return stride(from: 0, to: points.count - 1, by: Self.chunkSize).map { start in
            let end = min(start + Self.chunkSize, points.count - 1)
            var path = Path()
            path.addLines(Array(points[start...end]))
            return (path, color(at: Double(startIndex + start) * sampleStep))
        }
    }

    private static func makeRods(_ style: Style, count: Int, formula: [FormulaRod]) -> [Rod] {
        switch style {
        case .classic:
            return [Rod(length: 0.5, speed: 1, phase: 0), Rod(length: 0.5, speed: .pi, phase: 0)]
        case .digits:
            // Shrinking lengths (1, 1/2, 1/3, …) scaled so the chain reaches at most radius 1.
            let weights = (1...count).map { 1 / Double($0) }
            let total = weights.reduce(0, +)
            return (0..<count).map { k in
                let direction: Double = k.isMultiple(of: 2) ? 1 : -1
                return Rod(length: weights[k] / total, speed: direction * Double(PiDigits.all[k]), phase: 0)
            }
        case .drawPi:
            return PiOutline.terms.prefix(count).map { Rod(length: $0.length, speed: $0.speed, phase: $0.phase) }
        case .formula:
            // Scale so the fully stretched chain just reaches the unit circle.
            let total = max(formula.reduce(0) { $0 + $1.length }, 0.001)
            return formula.map { Rod(length: $0.length / total, speed: $0.speed, phase: 0) }
        }
    }
}
