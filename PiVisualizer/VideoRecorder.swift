import AVFoundation
import os
import CoreImage
import Observation
import ReplayKit
import AVKit
import SwiftUI

/// Records the visualization, and nothing else, to an MP4 with the app's sound.
///
/// ReplayKit captures the app's screen and audio; every video frame is cropped to the
/// visualization's frame (`crop`, kept current as tabs change), fitted into the clip's frame (set by
/// the first frame, at most 1080 px wide), and written with AVAssetWriter.
@MainActor
@Observable
final class VideoRecorder {
    static let shared = VideoRecorder()

    enum State: Equatable {
        case idle, starting, recording, finishing
    }

    private(set) var state = State.idle
    private(set) var startedAt: Date?
    /// The finished clip, waiting to be previewed.
    var finishedClip: URL?
    /// Why the last recording failed, if it did.
    var failure: String?
    var isRecording: Bool { state == .recording || state == .starting }

    /// The visualization's frame, in screen points. Set by `.recordingArea()`; read per frame on the
    /// writer's queue, hence the lock.
    nonisolated static let crop = OSAllocatedUnfairLock(initialState: CGRect.zero)
    @ObservationIgnored private var writer: ClipWriter?

    func toggle() {
        switch state {
        case .idle: start()
        case .recording: stop()
        case .starting, .finishing: break
        }
    }

    private func start() {
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else {
            failure = "Screen recording isn't available right now."
            return
        }
        recorder.isMicrophoneEnabled = false
        let screen = UIScreen.main
        let writer = ClipWriter(screenSize: screen.bounds.size)
        self.writer = writer
        state = .starting
        recorder.startCapture(handler: { buffer, type, error in
            guard error == nil else { return }
            writer.append(buffer, type: type)
        }, completionHandler: { error in
            Task { @MainActor in
                if let error {
                    self.state = .idle
                    self.writer = nil
                    self.failure = (error as NSError).code == RPRecordingErrorCode.userDeclined.rawValue
                        ? nil : error.localizedDescription
                } else {
                    self.state = .recording
                    self.startedAt = Date()
                }
            }
        })
    }

    private func stop() {
        state = .finishing
        let writer = self.writer
        RPScreenRecorder.shared().stopCapture { _ in
            writer?.finish { url in
                Task { @MainActor in
                    self.state = .idle
                    self.startedAt = nil
                    self.writer = nil
                    if let url { self.finishedClip = url } else { self.failure = "The clip couldn't be saved." }
                }
            }
        }
    }
}

/// Writes cropped frames and app audio to an MP4. Used only on its own serial queue.
private final class ClipWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "PiVisualizer.clip-writer")
    private let screenSize: CGSize
    private let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("Magic of π \(Int(Date().timeIntervalSince1970)).mp4")
    private let context = CIContext()

    private var writer: AVAssetWriter?
    private var video: AVAssetWriterInput?
    private var audio: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var outputSize = CGSize.zero
    private var started = false
    private var finished = false

    init(screenSize: CGSize) {
        self.screenSize = screenSize
    }

    func append(_ buffer: CMSampleBuffer, type: RPSampleBufferType) {
        queue.sync {
            guard !finished, CMSampleBufferDataIsReady(buffer) else { return }
            switch type {
            case .video: appendVideo(buffer)
            case .audioApp:
                // Audio before the first frame has nowhere to go.
                if started, let audio, audio.isReadyForMoreMediaData { audio.append(buffer) }
            default: break
            }
        }
    }

    func finish(_ completion: @escaping (URL?) -> Void) {
        queue.async { [self] in
            finished = true
            guard started, let writer else { return completion(nil) }
            video?.markAsFinished()
            audio?.markAsFinished()
            writer.finishWriting { [url] in completion(writer.status == .completed ? url : nil) }
        }
    }

    private func appendVideo(_ buffer: CMSampleBuffer) {
        guard let pixels = CMSampleBufferGetImageBuffer(buffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(buffer)
        let frame = CIImage(cvPixelBuffer: pixels)

        // Screen points → captured pixels. Core Image counts y from the bottom.
        let crop = VideoRecorder.crop.withLock { $0 }
        let scale = frame.extent.width / screenSize.width
        let region = CGRect(x: crop.minX * scale, y: frame.extent.height - crop.maxY * scale,
                            width: crop.width * scale, height: crop.height * scale).integral

        if !started {
            guard region.width > 16, region.height > 16, start(at: time, regionSize: region.size) else { return }
        }
        guard let video, video.isReadyForMoreMediaData, let adaptor, let pool = adaptor.pixelBufferPool else { return }
        var output: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &output)
        guard let output else { return }
        // Fit the area into the clip's frame, centred on black: after a tab switch it may have
        // a different shape from the first.
        let fit = min(outputSize.width / region.width, outputSize.height / region.height)
        let image = frame.cropped(to: region)
            .transformed(by: CGAffineTransform(translationX: -region.minX, y: -region.minY))
            .transformed(by: CGAffineTransform(scaleX: fit, y: fit))
            .transformed(by: CGAffineTransform(translationX: (outputSize.width - region.width * fit) / 2,
                                               y: (outputSize.height - region.height * fit) / 2))
        context.render(image.composited(over: CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: outputSize))),
                       to: output)
        adaptor.append(output, withPresentationTime: time)
    }

    /// Sets the writer up on the first frame, once the cropped size is known.
    private func start(at time: CMTime, regionSize: CGSize) -> Bool {
        // At most 1080 px wide, dimensions even for H.264.
        let fit = min(1, 1080 / regionSize.width)
        outputSize = CGSize(width: (regionSize.width * fit / 2).rounded() * 2,
                            height: (regionSize.height * fit / 2).rounded() * 2)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return false }
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: outputSize.width,
            AVVideoHeightKey: outputSize.height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 10_000_000],
        ])
        video.expectsMediaDataInRealTime = true
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000,
        ])
        audio.expectsMediaDataInRealTime = true
        guard writer.canAdd(video), writer.canAdd(audio) else { return false }
        writer.add(video)
        writer.add(audio)
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: outputSize.width,
            kCVPixelBufferHeightKey as String: outputSize.height,
        ])
        guard writer.startWriting() else { return false }
        writer.startSession(atSourceTime: time)
        self.writer = writer
        self.video = video
        self.audio = audio
        started = true
        return true
    }
}

extension View {
    /// Marks this view as the area a recording captures. `square` crops to the centred square,
    /// for the circular 2D visualizations.
    func recordingArea(square: Bool = false) -> some View {
        background(
            GeometryReader { geometry in
                let frame = geometry.frame(in: .global)
                Color.clear
                    .onAppear { Self.setCrop(frame, square: square) }
                    .onChange(of: frame) { _, new in Self.setCrop(new, square: square) }
            }
        )
    }

    private static func setCrop(_ frame: CGRect, square: Bool) {
        let area = area(frame, square: square)
        VideoRecorder.crop.withLock { $0 = area }
    }

    private static func area(_ frame: CGRect, square: Bool) -> CGRect {
        guard square else { return frame }
        let side = min(frame.width, frame.height)
        return CGRect(x: frame.midX - side / 2, y: frame.midY - side / 2, width: side, height: side)
    }
}

/// "0:12" while recording; shown in the control bar, outside the recorded area.
struct RecordingIndicator: View {
    let recorder = VideoRecorder.shared

    var body: some View {
        if recorder.isRecording {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let seconds = Int(timeline.date.timeIntervalSince(recorder.startedAt ?? timeline.date))
                Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
    }
}

/// The finished clip: play it, share it, or save it to Photos.
struct ClipPreview: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var saved = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VideoPlayerView(url: url)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                HStack(spacing: 12) {
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button(action: save) {
                        Label(saved ? "Saved" : "Save to Photos", systemImage: saved ? "checkmark" : "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(saved)
                }
                .controlSize(.large)
                if let saveError {
                    Text(saveError).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)
            .navigationTitle("Your clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func save() {
        UISaveVideoAtPathToSavedPhotosAlbum(url.path, nil, nil, nil)
        // The call reports errors through a selector; Photos permission is asked for automatically,
        // and if it's refused the Share sheet's "Save Video" still works.
        saved = true
        saveError = nil
    }
}

/// A looping video player.
private struct VideoPlayerView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        let player = AVQueuePlayer()
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        controller.player = player
        controller.showsPlaybackControls = true
        player.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var looper: AVPlayerLooper?
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
