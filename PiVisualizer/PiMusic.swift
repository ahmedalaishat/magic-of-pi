import AVFoundation
import Observation
import os

/// π as music: each digit plays a note of a two-octave C-major pentatonic scale (any sequence of
/// those notes sounds consonant), and close calls play a chord. A tiny synthesiser makes the
/// sound, so there are no audio files. Plays through the "ambient" session: it respects the
/// silent switch and mixes with other audio.
@MainActor
@Observable
final class PiMusic {
    static let shared = PiMusic()

    var isOn: Bool {
        didSet { UserDefaults.standard.set(isOn, forKey: Self.defaultsKey) }
    }

    @ObservationIgnored private let synth = Synth()
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var lastNote: TimeInterval = 0
    /// Faster playback is thinned to about 12 notes a second, so it stays a melody, not a buzz.
    private static let minInterval: TimeInterval = 0.085
    private static let defaultsKey = "musicOn"

    /// C D E G A, then the same an octave up: digit 0 is the lowest note, 9 the highest.
    private static let scale: [Double] = [261.63, 293.66, 329.63, 392.00, 440.00,
                                          523.25, 587.33, 659.25, 783.99, 880.00]

    private init() {
        isOn = UserDefaults.standard.object(forKey: Self.defaultsKey) as? Bool ?? true
    }

    func play(digit: UInt8) {
        guard isOn else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastNote >= Self.minInterval else { return }
        lastNote = now
        startIfNeeded()
        synth.trigger([Self.scale[Int(digit)]], loudness: 0.22)
    }

    /// A bright C-major chord for a close call or a finished drawing.
    func playChord() {
        guard isOn else { return }
        lastNote = ProcessInfo.processInfo.systemUptime
        startIfNeeded()
        synth.trigger([261.63, 329.63, 392.00, 523.25, 783.99], loudness: 0.12)
    }

    private func startIfNeeded() {
        guard engine == nil else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            let engine = AVAudioEngine()
            let format = engine.outputNode.inputFormat(forBus: 0)
            let node = synth.makeNode(sampleRate: format.sampleRate)
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode,
                           format: AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1))
            try engine.start()
            self.engine = engine
        } catch {
            // Sound is a nice-to-have: if audio can't start, the visuals carry on silently.
            isOn = false
        }
    }
}

/// A small polyphonic bell synth. New notes are queued under a lock by the main thread; the audio
/// thread only try-locks to collect them, so it never waits, and renders from its own voices.
///
/// The render loop avoids per-sample trigonometry: each voice is a unit vector rotated by a fixed
/// step every sample (its sine is the y component), overtones come from double/triple-angle
/// identities, and the decay is a per-sample multiplier. With no voice sounding it just writes
/// silence.
private final class Synth: @unchecked Sendable {
    private struct Voice {
        var x: Float = 1, y: Float = 0          // cos and sin of the phase
        var stepCos: Float = 1, stepSin: Float = 0
        var envelope: Float = 0, decay: Float = 0
        var attack: Float = 0, attackStep: Float = 0
        var loudness: Float = 0
        var active = false
    }

    private let pending = OSAllocatedUnfairLock(initialState: [(frequency: Double, loudness: Double)]())
    /// Older notes are nearly silent by the time a tenth overlaps them, so ten voices sound the same
    /// as more and cost less.
    private static let voiceCount = 10
    /// A voice below this level is inaudible and is freed.
    private static let silence: Float = 0.002
    private let voices = UnsafeMutablePointer<Voice>.allocate(capacity: voiceCount)
    private var activeCount = 0
    private var sampleRate: Double = 48_000

    init() {
        voices.initialize(repeating: Voice(), count: Self.voiceCount)
    }

    deinit {
        voices.deallocate()
    }

    func trigger(_ frequencies: [Double], loudness: Double) {
        pending.withLock { $0.append(contentsOf: frequencies.map { ($0, loudness) }) }
    }

    func makeNode(sampleRate: Double) -> AVAudioSourceNode {
        self.sampleRate = sampleRate
        return AVAudioSourceNode { [self] _, _, frameCount, audioBuffers in
            collectPending()
            let buffers = UnsafeMutableAudioBufferListPointer(audioBuffers)
            let frames = Int(frameCount)
            guard activeCount > 0 else {
                for buffer in buffers { memset(buffer.mData, 0, Int(buffer.mDataByteSize)) }
                return noErr
            }
            let out = buffers[0].mData!.assumingMemoryBound(to: Float.self)
            memset(out, 0, frames * MemoryLayout<Float>.size)
            // One voice at a time over the whole buffer, with its state in locals: a tight loop.
            for i in 0..<Self.voiceCount where voices[i].active {
                var v = voices[i]
                for frame in 0..<frames {
                    let s = v.y, c = v.x
                    // sin 2p = 2 sin p cos p; sin 3p = sin p (3 - 4 sin² p): a marimba/bell colour.
                    let tone = s + 0.28 * (2 * s * c) + 0.08 * (s * (3 - 4 * s * s))
                    out[frame] += v.loudness * v.envelope * v.attack * tone
                    v.x = c * v.stepCos - s * v.stepSin
                    v.y = s * v.stepCos + c * v.stepSin
                    v.envelope *= v.decay
                    v.attack = min(v.attack + v.attackStep, 1)
                }
                if v.envelope < Self.silence {
                    v.active = false
                    activeCount -= 1
                } else {
                    // Rotation drifts off the unit circle very slowly; pull it back once per buffer.
                    let length = (v.x * v.x + v.y * v.y).squareRoot()
                    v.x /= length
                    v.y /= length
                }
                voices[i] = v
            }
            // Gentle soft-clip so stacked chords never distort.
            for frame in 0..<frames {
                let sample = out[frame]
                out[frame] = sample / (1 + abs(sample))
            }
            for buffer in buffers.dropFirst() {
                memcpy(buffer.mData, out, frames * MemoryLayout<Float>.size)
            }
            return noErr
        }
    }

    private func collectPending() {
        // Swap the queue out rather than clearing it in place, which would copy on the audio thread.
        guard let notes = pending.withLockIfAvailable({ state -> [(frequency: Double, loudness: Double)] in
            let taken = state
            state = []
            return taken
        }), !notes.isEmpty else { return }
        for note in notes {
            // Use a free voice, or steal the quietest one.
            var slot = 0
            var quietest = Float.infinity
            for i in 0..<Self.voiceCount {
                if !voices[i].active { slot = i; quietest = -1; break }
                if voices[i].envelope < quietest { quietest = voices[i].envelope; slot = i }
            }
            if quietest < 0 { activeCount += 1 }
            let step = 2 * Double.pi * note.frequency / sampleRate
            voices[slot] = Voice(x: 1, y: 0, stepCos: Float(cos(step)), stepSin: Float(sin(step)),
                                 // Bell-like decay: amplitude falls by e every 0.32 s.
                                 envelope: 1, decay: Float(exp(-1 / (0.32 * sampleRate))),
                                 // 4 ms strike.
                                 attack: 0, attackStep: Float(1 / (0.004 * sampleRate)),
                                 loudness: Float(note.loudness), active: true)
        }
    }
}
