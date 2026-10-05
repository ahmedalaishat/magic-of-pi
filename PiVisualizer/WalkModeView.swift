import SwiftUI
import SceneKit

/// π's digits steering a glowing path through 3D space; drag to spin, pinch to zoom.
struct WalkModeView: View {
    @Bindable var model: WalkModel
    @State private var showingOptions = false

    var body: some View {
        VStack(spacing: 14) {
            scene
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .frame(maxHeight: .infinity)
                .recordingArea()
                .overlay(alignment: .topLeading) {
                    CounterBadge { "\(model.steps.formatted()) / \(model.digitCount.formatted()) digits" }
                }
            ControlBar(isPlaying: model.isPlaying, onRestart: model.restart, onTogglePlay: model.togglePlay,
                       onOptions: { showingOptions = true }, shots: CameraShot.allCases, onShot: model.play)
        }
        .task(id: model.isPlaying) {
            await runFrameLoop(while: { model.isPlaying }, tick: model.tick(seconds:))
        }
        .sheet(isPresented: $showingOptions) {
            OptionsSheet(topic: .walk, speed: $model.speed, speedRange: 2...50_000, hapticsOn: $model.hapticsOn) {
                Section("Digits of π") {
                    Picker("Digits", selection: Binding(get: { model.digitCount }, set: { model.setDigitCount($0) })) {
                        ForEach(WalkModel.countOptions, id: \.self) {
                            Text($0.formatted(.number.notation(.compactName))).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    private var scene: some View {
        WalkSceneHost(model: model)
            // A new digit count is a new walk, so rebuild the scene rather than patch it.
            .id(model.digitCount)
    }
}

/// Reads the per-frame playback state in its own body, so only the 3D view updates each frame.
private struct WalkSceneHost: View {
    let model: WalkModel

    var body: some View {
        WalkSceneView(path: model.path, position: model.position, speed: model.speed,
                      isPlaying: model.isPlaying, shot: model.shotRequest)
    }
}

struct WalkSceneView: UIViewRepresentable {
    let path: WalkPath
    let position: Double
    let speed: Double
    let isPlaying: Bool
    let shot: ShotRequest?

    func makeCoordinator() -> WalkScene { WalkScene(path: path) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.camera
        view.delegate = context.coordinator
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 120
        // The director camera moves every frame, even while paused.
        view.rendersContinuously = true
        context.coordinator.attachGestures(to: view)
        // A rebuilt scene (new digit count, or entering full screen) shouldn't replay the last move.
        context.coordinator.skipShot(upTo: shot)
        context.coordinator.update(position: position, speed: speed, isPlaying: isPlaying, shot: shot)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.update(position: position, speed: speed, isPlaying: isPlaying, shot: shot)
    }
}

/// The scene for one walk, filmed by a "director" camera. The whole path is uploaded once as a line
/// mesh; playback only changes how many segments are drawn, so even 100,000 steps cost nothing.
///
/// Every rendered frame the camera eases (with critically damped springs) to a spot in front of
/// the head, a little above it, looking back as the walk comes towards it. "In front" follows the
/// walk's average heading, not each zig-zag step, and the distance grows with playback speed so
/// the recent trail stays in view. Paused, it slowly circles the head. The viewer's drag and pinch
/// add an offset on top, and a double-tap hands control back.
final class WalkScene: NSObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    let camera = SCNNode()
    private let path: WalkPath
    private let head = SCNNode()
    private let segments: SCNGeometryElement
    /// The newest steps, drawn a second time so the head's tail glows brighter.
    private let tail: SCNGeometryElement
    private static let tailLength = 40

    /// Written on the main thread, read on SceneKit's render thread.
    private struct Controls {
        var position: Double = 0
        var speed: Double = 300
        var isPlaying = false
        var yawOffset: Float = 0
        var pitchOffset: Float = 0
        var zoom: Float = 1
        var shot: ShotRequest?
        var cancelShot = false
    }
    private var controls = Controls()
    private let lock = NSLock()

    // Camera state, render thread only.
    private var focus = SIMD3<Float>.zero, focusVelocity = SIMD3<Float>.zero
    private var distance: Float = 8, distanceVelocity: Float = 0
    /// The walk's smoothed heading, flattened to the horizontal plane.
    private var heading = SIMD3<Float>(0, 0, 1), headingVelocity = SIMD3<Float>.zero
    /// Extra turn around the head while paused.
    private var circling: Float = 0
    private var lastTime: TimeInterval?
    private var clock: Float = 0
    /// The scripted move in progress: when it started, and the angle it started from.
    private var activeShot: (shot: CameraShot, start: Float, angle: Float)?
    private var lastShotSerial = 0

    init(path: WalkPath) {
        self.path = path

        let count = path.points.count
        let vertices = SCNGeometrySource(vertices: path.points.map { SCNVector3($0) })
        // Colour drifts along the walk from cyan through violet to pink, so you can read its history.
        // Computed directly (no UIColor per vertex): a million-step walk has a million vertices.
        var colors = [SIMD4<Float>](repeating: .zero, count: count)
        for i in 0..<count {
            let t = Float(i) / Float(max(count - 1, 1))
            colors[i] = Self.rgb(hue: (0.5 + 0.45 * t).truncatingRemainder(dividingBy: 1), saturation: 0.75, alpha: 0.85)
        }
        let colorSource = SCNGeometrySource(
            data: colors.withUnsafeBufferPointer { Data(buffer: $0) },
            semantic: .color, vectorCount: count, usesFloatComponents: true,
            componentsPerVector: 4, bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: MemoryLayout<SIMD4<Float>>.stride)
        var indices = [UInt32](repeating: 0, count: max(count - 1, 0) * 2)
        for i in 0..<max(count - 1, 0) {
            indices[2 * i] = UInt32(i)
            indices[2 * i + 1] = UInt32(i + 1)
        }
        segments = SCNGeometryElement(indices: indices, primitiveType: .line)
        tail = SCNGeometryElement(indices: indices, primitiveType: .line)

        let geometry = SCNGeometry(sources: [vertices, colorSource], elements: [segments, tail])
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor.white
        // Additive glow where the walk crosses itself.
        material.blendMode = .add
        material.writesToDepthBuffer = false
        geometry.materials = [material, material]
        let walk = SCNNode(geometry: geometry)
        scene.rootNode.addChildNode(walk)

        let sphere = SCNSphere(radius: 1)
        sphere.firstMaterial?.lightingModel = .constant
        sphere.firstMaterial?.diffuse.contents = UIColor.white
        head.geometry = sphere
        scene.rootNode.addChildNode(head)

        // Fog fades the far side of the walk into the dark, which makes its depth readable.
        scene.fogColor = UIColor.black
        scene.fogDensityExponent = 1.5

        let lens = SCNCamera()
        lens.zNear = 0.05
        lens.zFar = 20_000
        // Measure the field of view across the width, so tall full-screen views don't crop the sides.
        lens.projectionDirection = .horizontal
        lens.fieldOfView = 55
        lens.wantsHDR = true
        lens.bloomIntensity = 1.4
        lens.bloomThreshold = 0.25
        lens.bloomBlurRadius = 10
        camera.camera = lens
        scene.rootNode.addChildNode(camera)
        super.init()
        place(at: 0)
    }

    func skipShot(upTo shot: ShotRequest?) {
        lastShotSerial = shot?.serial ?? 0
    }

    func update(position: Double, speed: Double, isPlaying: Bool, shot: ShotRequest?) {
        let steps = min(Int(position), path.points.count - 1)
        segments.primitiveRange = NSRange(location: 0, length: steps)
        let tailStart = max(steps - Self.tailLength, 0)
        tail.primitiveRange = NSRange(location: tailStart, length: steps - tailStart)
        lock.withLock {
            controls.position = position
            controls.speed = speed
            controls.isPlaying = isPlaying
            controls.shot = shot
        }
    }

    // MARK: Gestures

    func attachGestures(to view: SCNView) {
        view.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(orbit(_:))))
        view.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(zoom(_:))))
        let reset = UITapGestureRecognizer(target: self, action: #selector(resetView))
        reset.numberOfTapsRequired = 2
        view.addGestureRecognizer(reset)
    }

    @objc private func orbit(_ gesture: UIPanGestureRecognizer) {
        let delta = gesture.translation(in: gesture.view)
        gesture.setTranslation(.zero, in: gesture.view)
        lock.withLock {
            controls.yawOffset -= Float(delta.x) * 0.008
            controls.pitchOffset = min(max(controls.pitchOffset + Float(delta.y) * 0.006, -1.1), 1.0)
        }
    }

    @objc private func zoom(_ gesture: UIPinchGestureRecognizer) {
        let scale = Float(gesture.scale)
        gesture.scale = 1
        lock.withLock { controls.zoom = min(max(controls.zoom / scale, 0.15), 6) }
    }

    @objc private func resetView() {
        lock.withLock {
            controls.yawOffset = 0
            controls.pitchOffset = 0
            controls.zoom = 1
            controls.cancelShot = true
        }
    }

    // MARK: Director

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt = Float(min(time - (lastTime ?? time), 0.1))
        lastTime = time
        clock += dt
        place(at: dt)
    }

    /// HSV (full brightness) to RGB.
    private static func rgb(hue: Float, saturation: Float, alpha: Float) -> SIMD4<Float> {
        let h = hue * 6, sector = Int(h) % 6, f = h - Float(Int(h))
        let p = 1 - saturation, q = 1 - saturation * f, t = 1 - saturation * (1 - f)
        let (r, g, b): (Float, Float, Float) = switch sector {
        case 0: (1, t, p)
        case 1: (q, 1, p)
        case 2: (p, 1, t)
        case 3: (p, q, 1)
        case 4: (t, p, 1)
        default: (1, p, q)
        }
        return SIMD4(r, g, b, alpha)
    }

    /// Moves the camera one frame towards the current shot.
    private func place(at dt: Float) {
        let c = lock.withLock { controls }
        let points = path.points
        let index = min(Int(c.position), points.count - 1)
        let next = min(index + 1, points.count - 1)
        // Glide the head along the step it is taking, so slow playback moves smoothly.
        let headPosition = simd_mix(points[index], points[next], SIMD3(repeating: Float(c.position - Double(index))))

        // Heading: where the last ~1.5 seconds of steps have been going. Single steps zig-zag in
        // ten directions; the average drift is what reads as "forward".
        let window = min(max(Int(c.speed * 1.5), 20), 3_000)
        var drift = headPosition - points[max(index - window, 0)]
        drift.y = 0
        let targetHeading = simd_length(drift) > 0.5 ? simd_normalize(drift) : heading

        // Close when slow; further back when fast, so the trail the head is leaving stays in view.
        let targetDistance = (6 + 1.1 * Float(c.speed).squareRoot()) * c.zoom

        if dt == 0 {
            focus = headPosition
            distance = targetDistance
            heading = targetHeading
        } else {
            // Stiff on the head so it never drifts off-screen; soft on heading so the camera
            // swings round gently when the walk changes course.
            Motion.spring(&focus, &focusVelocity, to: headPosition, omega: 7, dt: dt)
            Motion.spring(&distance, &distanceVelocity, to: targetDistance, omega: 1.5, dt: dt)
            Motion.spring(&heading, &headingVelocity, to: targetHeading, omega: 0.9, dt: dt)
        }
        if !c.isPlaying { circling += dt * 0.15 }

        let flat = simd_length(heading) > 0.01 ? simd_normalize(heading) : SIMD3<Float>(0, 0, 1)
        let turn = simd_quatf(angle: c.yawOffset + circling, axis: SIMD3(0, 1, 0))
        let forward = turn.act(flat)
        let pitch = min(max(0.38 + c.pitchOffset, -1.2), 1.3)
        let offset = (forward * cos(pitch) + SIMD3(0, 1, 0) * sin(pitch)) * distance
        var eye = focus + offset
        var target = focus

        // A scripted move takes over, easing out of the follow camera and back into it.
        if let request = c.shot, request.serial != lastShotSerial {
            lastShotSerial = request.serial
            let around = request.shot == .orbit ? headPosition : (path.lower[index] + path.upper[index]) / 2
            activeShot = (request.shot, clock, atan2(eye.x - around.x, eye.z - around.z))
        }
        if c.cancelShot {
            lock.withLock { controls.cancelShot = false }
            activeShot = nil
        }
        if let shot = activeShot {
            let t = (clock - shot.start) / shot.shot.duration
            if t >= 1 {
                activeShot = nil
            } else {
                let pose = shotPose(shot.shot, at: t, angle: shot.angle, head: headPosition, index: index)
                let blend = Motion.ease(t / 0.2) * (1 - Motion.ease((t - 0.8) / 0.2))
                eye = simd_mix(eye, pose.eye, SIMD3(repeating: blend))
                target = simd_mix(target, pose.target, SIMD3(repeating: blend))
            }
        }
        camera.simdPosition = eye
        // Pin "up" to the world's, so the camera never rolls after looking straight down.
        camera.simdLook(at: target, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))

        let viewDistance = simd_distance(eye, target)
        scene.fogStartDistance = CGFloat(viewDistance * 1.2)
        scene.fogEndDistance = CGFloat(viewDistance * 6 + 20)

        head.simdPosition = headPosition
        // Constant size on screen, whatever the camera distance.
        head.simdScale = SIMD3(repeating: max(simd_distance(camera.simdPosition, headPosition), 0.5) * 0.009)
    }

    /// Where a scripted move puts the camera at progress t (0...1), and what it looks at.
    private func shotPose(_ shot: CameraShot, at t: Float, angle: Float, head: SIMD3<Float>, index: Int)
        -> (eye: SIMD3<Float>, target: SIMD3<Float>) {
        let lower = path.lower[index], upper = path.upper[index]
        let center = (lower + upper) / 2
        let radius = max(simd_length(upper - lower) / 2, 3)
        func around(_ point: SIMD3<Float>, distance: Float, yaw: Float, pitch: Float) -> SIMD3<Float> {
            point + SIMD3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
        }
        switch shot {
        case .overview:
            // Pull out to the whole walk so far and circle it once.
            return (around(center, distance: radius * 1.9 + 6, yaw: angle + 2 * .pi * Motion.ease(t), pitch: 0.45), center)
        case .orbit:
            return (around(head, distance: distance, yaw: angle + 2 * .pi * Motion.ease(t), pitch: 0.3), head)
        case .topDown:
            // Almost straight down (a small tilt keeps "up" defined), turning slowly.
            return (around(center, distance: radius * 2.2 + 8, yaw: angle + 0.8 * t, pitch: 1.35), center)
        case .flythrough:
            // Ride along the walk from its first digit to the head, over a smoothed path so the
            // camera doesn't shake with every zig-zag step.
            let u = Motion.ease((t - 0.1) / 0.8)
            let at = Int(u * Float(index))
            let width = max(index / 150, 4), lead = max(index / 60, 8)
            let here = smoothedPoint(at, width: width, limit: index)
            let ahead = smoothedPoint(min(at + lead, index), width: width, limit: index)
            let back = simd_length(here - ahead) > 0.01 ? simd_normalize(here - ahead) : SIMD3<Float>(0, 0, 1)
            let height = 3 + Float(width).squareRoot() * 1.5
            return (here + back * height * 1.2 + SIMD3(0, height, 0), ahead)
        }
    }

    /// The average of the walk's points around index i, sampled sparsely.
    private func smoothedPoint(_ i: Int, width: Int, limit: Int) -> SIMD3<Float> {
        let samples = 24
        var sum = SIMD3<Float>.zero
        for k in 0..<samples {
            let j = min(max(i - width + 2 * width * k / (samples - 1), 0), limit)
            sum += path.points[j]
        }
        return sum / Float(samples)
    }
}
