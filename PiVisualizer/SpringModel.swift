import SwiftUI
import Observation
import simd

/// The 1 : π rods' trail with time as height: each turn rises a little, so the loops stack into a
/// spring. Seen from above the stack is the flat drawing; the near-miss turns (7, 106, 113) are
/// the loops that land almost exactly on turn 0's.
struct SpringPath {
    static let pointsPerTurn = 400
    /// Turn 0 and the turns that nearly close it, where π ≈ 22/7, 333/106 and 355/113.
    static let highlightedTurns = [0, 7, 106, 113]
    /// Height of the whole spring, whatever the number of turns; the rods reach radius 1.
    static let height: Float = 4

    let turns: Int
    let points: [SIMD3<Float>]
    let colors: [SIMD4<Float>]

    init(turns: Int) {
        self.turns = turns
        let count = turns * Self.pointsPerTurn + 1
        let rise = Self.height / Float(turns)
        var points: [SIMD3<Float>] = []
        var colors: [SIMD4<Float>] = []
        // Fainter loops in taller stacks, so overlaps add up to colour rather than white and the
        // highlighted loops stand out.
        let alpha = min(0.8, 25 / Float(turns))
        points.reserveCapacity(count)
        colors.reserveCapacity(count)
        for i in 0..<count {
            // Double precision for the angles: after hundreds of turns π·θ is in the thousands.
            let theta = 2 * Double.pi * Double(i) / Double(Self.pointsPerTurn)
            let x = 0.5 * cos(theta) + 0.5 * cos(.pi * theta)
            let z = -(0.5 * sin(theta) + 0.5 * sin(.pi * theta))
            let turn = Double(i) / Double(Self.pointsPerTurn)
            points.append(SIMD3(Float(x), Float(turn) * rise, Float(z)))
            // Hue cycles every 7 turns, like the flat drawing, so 22/7's loop matches turn 0's colour.
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(hue: CGFloat((turn / 7).truncatingRemainder(dividingBy: 1)), saturation: 0.7, brightness: 1, alpha: 1)
                .getRed(&r, green: &g, blue: &b, alpha: &a)
            colors.append(SIMD4(Float(r), Float(g), Float(b), alpha))
        }
        self.points = points
        self.colors = colors
    }

    /// The pen's position after `turns` turns, between samples.
    func point(atTurn turn: Double) -> SIMD3<Float> {
        let exact = turn * Double(Self.pointsPerTurn)
        let i = min(Int(exact), points.count - 1), j = min(i + 1, points.count - 1)
        return simd_mix(points[i], points[j], SIMD3(repeating: Float(exact - Double(i))))
    }
}

@MainActor
@Observable
final class SpringModel {
    static let turnOptions = [20, 120, 360]
    private(set) var turnCount = 120
    /// Turns drawn so far.
    private(set) var position: Double = 0
    var isPlaying = false
    /// Turns per second.
    var speed: Double = 1
    var hapticsOn = true
    private(set) var shotRequest: ShotRequest?

    @ObservationIgnored private(set) var path = SpringPath(turns: 120)
    @ObservationIgnored private let haptics = DigitHaptics()

    var isFinished: Bool { position >= Double(turnCount) }

    /// The best fraction for π the spring has passed, if any.
    var latestConvergent: RodsModel.Fraction? {
        RodsModel.convergents.last { Double($0.turns) <= position + 1e-9 }
    }

    func setTurnCount(_ count: Int) {
        turnCount = count
        path = SpringPath(turns: count)
        restart()
    }

    func restart() {
        position = 0
    }

    func togglePlay() {
        if isFinished { restart() }
        isPlaying.toggle()
    }

    func play(_ shot: CameraShot) {
        shotRequest = ShotRequest(shot: shot, serial: (shotRequest?.serial ?? 0) + 1)
    }

    func tick(seconds: Double) {
        guard isPlaying else { return }
        let before = Int(position)
        position = min(position + speed * seconds, Double(turnCount))
        if Int(position) > before {
            let turn = Int(position)
            let closes = SpringPath.highlightedTurns.contains(turn)
            if hapticsOn { haptics.tap(intensity: closes ? 1 : 0.4, sharpness: closes ? 0.9 : 0.3) }
            // Turn n plays π's n-th digit; a close call plays a chord.
            if closes { PiMusic.shared.playChord() } else { PiMusic.shared.play(digit: PiDigits.all[turn]) }
        }
        if isFinished { isPlaying = false }
    }
}
