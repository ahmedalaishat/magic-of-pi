import SwiftUI
import Observation
import simd

/// π's digits as a walk in 3D: each digit takes one unit step in its own direction.
struct WalkPath {
    /// Digit d points at azimuth 36°·d, alternately up and down: the 10 non-polar vertices of an
    /// icosahedron. They sum to zero, so any drift in the walk comes from π's digits, not the layout.
    static let directions: [SIMD3<Float>] = (0..<10).map { d in
        let azimuth = Float(d) * .pi / 5
        let rise = 1 / Float(5).squareRoot(), spread = 2 / Float(5).squareRoot()
        return SIMD3(cos(azimuth) * spread, d.isMultiple(of: 2) ? rise : -rise, sin(azimuth) * spread)
    }

    /// The walk's positions: point k is where it stands after k digits.
    let points: [SIMD3<Float>]
    /// Bounding box of the first k steps (points 0...k), for framing the walk as it grows.
    let lower: [SIMD3<Float>]
    let upper: [SIMD3<Float>]

    init(steps: Int) {
        var points = [SIMD3<Float>.zero]
        var lower = [SIMD3<Float>.zero], upper = [SIMD3<Float>.zero]
        points.reserveCapacity(steps + 1)
        for digit in PiDigits.all.prefix(steps) {
            let next = points[points.count - 1] + Self.directions[Int(digit)]
            points.append(next)
            lower.append(simd_min(lower[lower.count - 1], next))
            upper.append(simd_max(upper[upper.count - 1], next))
        }
        self.points = points
        self.lower = lower
        self.upper = upper
    }
}

/// Scripted camera moves; each one plays, then hands back to the follow camera.
enum CameraShot: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case orbit = "Orbit"
    case flythrough = "Fly-through"
    case topDown = "Top view"

    var id: Self { self }

    var icon: String {
        switch self {
        case .overview: "rotate.3d"
        case .orbit: "arrow.triangle.2.circlepath"
        case .flythrough: "airplane"
        case .topDown: "square.3.layers.3d.down.right"
        }
    }

    /// Seconds, including easing out of and back into the follow camera.
    var duration: Float {
        switch self {
        case .overview: 7
        case .orbit: 5
        case .flythrough: 8
        case .topDown: 6
        }
    }
}

/// A request to play a shot; `serial` makes tapping the same shot twice start it again.
struct ShotRequest: Equatable {
    let shot: CameraShot
    let serial: Int
}

@MainActor
@Observable
final class WalkModel {
    static let countOptions = [1_000, 10_000, 100_000, 1_000_000]

    private(set) var digitCount: Int
    /// Steps taken so far; fractional while playing.
    private(set) var position: Double = 0
    var isPlaying = false
    /// Steps per second.
    var speed: Double = Stored.value("walk.speed", default: 300) { didSet { Stored.set(speed, "walk.speed") } }
    var hapticsOn: Bool = Stored.value("walk.haptics", default: true) { didSet { Stored.set(hapticsOn, "walk.haptics") } }

    private(set) var shotRequest: ShotRequest?
    @ObservationIgnored private(set) var path: WalkPath
    @ObservationIgnored private let haptics = DigitHaptics()

    var steps: Int { Int(position) }
    var isFinished: Bool { steps >= digitCount }
    var currentDigit: Int { Int(PiDigits.all[max(steps - 1, 0)]) }

    init() {
        let count = Stored.choice("walk.digits", among: Self.countOptions, default: 10_000)
        digitCount = count
        path = WalkPath(steps: count)
    }

    func setDigitCount(_ count: Int) {
        digitCount = count
        Stored.set(count, "walk.digits")
        path = WalkPath(steps: count)
        restart()
    }

    func restart() {
        position = 0
    }

    /// Stands the walk on digit `steps`, choosing the shortest walk that reaches it.
    func jump(to steps: Int) {
        isPlaying = false
        let count = Self.countOptions.first { $0 >= steps } ?? Self.countOptions.last!
        if count != digitCount { setDigitCount(count) }
        position = Double(min(steps, digitCount))
    }

    func play(_ shot: CameraShot) {
        shotRequest = ShotRequest(shot: shot, serial: (shotRequest?.serial ?? 0) + 1)
    }

    func togglePlay() {
        if isFinished { restart() }
        isPlaying.toggle()
    }

    func tick(seconds: Double) {
        guard isPlaying else { return }
        let before = steps
        position = min(position + speed * seconds, Double(digitCount))
        if steps > before {
            if hapticsOn { haptics.play(digit: PiDigits.all[steps - 1]) }
            PiMusic.shared.play(digit: PiDigits.all[steps - 1])
        }
        if isFinished { isPlaying = false }
    }
}
