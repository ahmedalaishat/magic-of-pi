import CoreHaptics
import QuartzCore

/// Short haptic taps. Per digit, low digits feel soft and dull and high digits strong and crisp,
/// so π's sequence comes through as a rhythm.
final class DigitHaptics {
    private var engine: CHHapticEngine?
    private var lastPlayed: CFTimeInterval = 0
    /// Faster playback would blur into a buzz, so taps are spaced at least this far apart.
    private let minInterval: CFTimeInterval = 0.045

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.resetHandler = { [weak self] in try? self?.engine?.start() }
        try? engine?.start()
    }

    func play(digit: UInt8) {
        let level = Float(digit) / 9
        tap(intensity: 0.35 + 0.65 * level, sharpness: 0.1 + 0.9 * level)
    }

    func tap(intensity: Float, sharpness: Float) {
        guard let engine else { return }
        let now = CACurrentMediaTime()
        guard now - lastPlayed >= minInterval else { return }
        lastPlayed = now

        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: 0)
        // A dropped tap is harmless, so playback errors are ignored.
        try? engine.makePlayer(with: CHHapticPattern(events: [event], parameters: []))
            .start(atTime: CHHapticTimeImmediate)
    }
}
