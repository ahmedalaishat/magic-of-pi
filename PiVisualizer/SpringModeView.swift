import SwiftUI
import SceneKit

/// The 1 : π rods' loops stacked into a spring, so near-misses show as loops lining up.
struct SpringModeView: View {
    @Bindable var model: SpringModel
    @State private var showingOptions = false

    static let shots: [CameraShot] = [.overview, .orbit, .topDown]

    var body: some View {
        VStack(spacing: 14) {
            scene
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .frame(maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    CounterBadge { String(format: "%.2f / %d turns", model.position, model.turnCount) }
                }
            SpringReadout(model: model).infoCard()
            ControlBar(isPlaying: model.isPlaying, onRestart: model.restart, onTogglePlay: model.togglePlay,
                       onOptions: { showingOptions = true }, shots: Self.shots, onShot: model.play)
        }
        .task(id: model.isPlaying) {
            await runFrameLoop(while: { model.isPlaying }, tick: model.tick(seconds:))
        }
        .sheet(isPresented: $showingOptions) {
            OptionsSheet(topic: .spring, speed: $model.speed, speedRange: 0.05...20, hapticsOn: $model.hapticsOn) {
                Section("Turns") {
                    Picker("Turns", selection: Binding(get: { model.turnCount }, set: { model.setTurnCount($0) })) {
                        ForEach(SpringModel.turnOptions, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    private var scene: some View {
        SpringSceneHost(model: model)
            // A new turn count is a new spring, so rebuild the scene rather than patch it.
            .id(model.turnCount)
    }
}

/// Reads the per-frame playback state in its own body, so only the 3D view updates each frame.
private struct SpringSceneHost: View {
    let model: SpringModel

    var body: some View {
        SpringSceneView(path: model.path, position: model.position, isPlaying: model.isPlaying,
                        shot: model.shotRequest)
    }
}

/// The latest near-miss, in its own view because it depends on the playback position.
private struct SpringReadout: View {
    let model: SpringModel

    var body: some View {
        Group {
            if let fraction = model.latestConvergent {
                Text("Turn \(fraction.turns)'s loop nearly lines up with turn 0 · π ≈ \(fraction.numerator)/\(fraction.turns)")
            } else {
                Text("White loops are turn 0 and the near-misses · try Top view")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(height: 36)
    }
}

struct SpringSceneView: UIViewRepresentable {
    let path: SpringPath
    let position: Double
    let isPlaying: Bool
    let shot: ShotRequest?

    func makeCoordinator() -> SpringScene { SpringScene(path: path) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.camera
        view.delegate = context.coordinator
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 120
        view.rendersContinuously = true
        context.coordinator.attachGestures(to: view)
        // A rebuilt scene (new turn count, or entering full screen) shouldn't replay the last move.
        context.coordinator.skipShot(upTo: shot)
        context.coordinator.update(position: position, isPlaying: isPlaying, shot: shot)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.update(position: position, isPlaying: isPlaying, shot: shot)
    }
}

/// The spring scene. Like the walk, the whole trail is uploaded once and playback only changes
/// how much is drawn. The camera circles the spring's axis and rises with the pen.
final class SpringScene: NSObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    let camera = SCNNode()
    private let lens = SCNCamera()
    private static let fieldOfView: Float = 55
    private let path: SpringPath
    private let head = SCNNode()
    private let trail: SCNGeometryElement
    /// One element per highlighted turn, drawn again in white over that turn's loop.
    private let rings: [(turn: Int, element: SCNGeometryElement)]

    /// Written on the main thread, read on SceneKit's render thread.
    private struct Controls {
        var position: Double = 0
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
    private var focusHeight: Float = 0, focusVelocity: Float = 0
    private var yaw: Float = 0.5
    private var lastTime: TimeInterval?
    private var clock: Float = 0
    private var activeShot: (shot: CameraShot, start: Float, angle: Float)?
    private var lastShotSerial = 0

    init(path: SpringPath) {
        self.path = path
        let count = path.points.count
        let vertices = SCNGeometrySource(vertices: path.points.map { SCNVector3($0) })
        let colorSource = SCNGeometrySource(
            data: path.colors.withUnsafeBufferPointer { Data(buffer: $0) },
            semantic: .color, vectorCount: count, usesFloatComponents: true,
            componentsPerVector: 4, bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: MemoryLayout<SIMD4<Float>>.stride)
        let indices = (0..<UInt32(count - 1)).flatMap { [$0, $0 + 1] }
        trail = SCNGeometryElement(indices: indices, primitiveType: .line)
        rings = SpringPath.highlightedTurns.filter { $0 < path.turns }.map { turn in
            (turn, SCNGeometryElement(indices: indices, primitiveType: .line))
        }

        func glowMaterial() -> SCNMaterial {
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = UIColor.white
            // Additive, so overlapping loops glow brighter.
            material.blendMode = .add
            material.writesToDepthBuffer = false
            return material
        }
        let trailGeometry = SCNGeometry(sources: [vertices, colorSource], elements: [trail])
        trailGeometry.materials = [glowMaterial()]
        scene.rootNode.addChildNode(SCNNode(geometry: trailGeometry))

        // The highlighted loops share the trail's points but are coloured plain white.
        let white = SCNGeometrySource(
            data: [SIMD4<Float>](repeating: SIMD4(1, 1, 1, 1), count: count).withUnsafeBufferPointer { Data(buffer: $0) },
            semantic: .color, vectorCount: count, usesFloatComponents: true,
            componentsPerVector: 4, bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: MemoryLayout<SIMD4<Float>>.stride)
        let ringGeometry = SCNGeometry(sources: [vertices, white], elements: rings.map(\.element))
        ringGeometry.materials = rings.map { _ in glowMaterial() }
        scene.rootNode.addChildNode(SCNNode(geometry: ringGeometry))

        // A faint beam rising through the start point: a loop that nearly closes passes through it.
        let start = path.points[0]
        let beamSource = SCNGeometrySource(vertices: [SCNVector3(start.x, -0.2, start.z),
                                                      SCNVector3(start.x, SpringPath.height + 0.2, start.z)])
        let beam = SCNGeometry(sources: [beamSource], elements: [SCNGeometryElement(indices: [UInt16(0), 1], primitiveType: .line)])
        let beamMaterial = SCNMaterial()
        beamMaterial.lightingModel = .constant
        beamMaterial.diffuse.contents = UIColor.white.withAlphaComponent(0.35)
        beamMaterial.blendMode = .add
        beam.materials = [beamMaterial]
        scene.rootNode.addChildNode(SCNNode(geometry: beam))

        let sphere = SCNSphere(radius: 1)
        sphere.firstMaterial?.lightingModel = .constant
        sphere.firstMaterial?.diffuse.contents = UIColor.white
        head.geometry = sphere
        scene.rootNode.addChildNode(head)

        scene.fogColor = UIColor.black
        scene.fogDensityExponent = 1.5

        lens.zNear = 0.02
        lens.zFar = 1_000
        lens.projectionDirection = .horizontal
        lens.fieldOfView = CGFloat(Self.fieldOfView)
        lens.wantsHDR = true
        lens.bloomIntensity = 1.3
        // Only the brightest lines (the highlighted loops, the head) bloom.
        lens.bloomThreshold = 0.6
        lens.bloomBlurRadius = 8
        camera.camera = lens
        scene.rootNode.addChildNode(camera)
        super.init()
        place(at: 0)
    }

    func skipShot(upTo shot: ShotRequest?) {
        lastShotSerial = shot?.serial ?? 0
    }

    func update(position: Double, isPlaying: Bool, shot: ShotRequest?) {
        let drawn = min(Int(position * Double(SpringPath.pointsPerTurn)), path.points.count - 1)
        trail.primitiveRange = NSRange(location: 0, length: drawn)
        for ring in rings {
            let first = ring.turn * SpringPath.pointsPerTurn
            ring.element.primitiveRange = NSRange(location: first, length: min(max(drawn - first, 0), SpringPath.pointsPerTurn))
        }
        lock.withLock {
            controls.position = position
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
            controls.pitchOffset = min(max(controls.pitchOffset + Float(delta.y) * 0.006, -1.1), 1.1)
        }
    }

    @objc private func zoom(_ gesture: UIPinchGestureRecognizer) {
        let scale = Float(gesture.scale)
        gesture.scale = 1
        lock.withLock { controls.zoom = min(max(controls.zoom / scale, 0.2), 5) }
    }

    @objc private func resetView() {
        lock.withLock {
            controls.yawOffset = 0
            controls.pitchOffset = 0
            controls.zoom = 1
            controls.cancelShot = true
        }
    }

    // MARK: Camera

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt = Float(min(time - (lastTime ?? time), 0.1))
        lastTime = time
        clock += dt
        place(at: dt)
    }

    private func place(at dt: Float) {
        let c = lock.withLock { controls }
        let pen = path.point(atTurn: c.position)

        // Circle the spring's axis at the pen's height, a little above it, looking slightly down.
        if dt == 0 {
            focusHeight = pen.y
        } else {
            Motion.spring(&focusHeight, &focusVelocity, to: pen.y, omega: 3, dt: dt)
        }
        yaw += dt * (c.isPlaying ? 0.18 : 0.1)
        let axis = SIMD3<Float>(0, focusHeight, 0)
        var target = axis
        var fieldOfView = Self.fieldOfView
        var eye = Motion.orbit(axis, distance: 3.4 * c.zoom, yaw: yaw + c.yawOffset,
                               pitch: min(max(0.35 + c.pitchOffset, -1.3), 1.4))

        if let request = c.shot, request.serial != lastShotSerial {
            lastShotSerial = request.serial
            activeShot = (request.shot, clock, atan2(eye.x, eye.z))
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
                let pose = shotPose(shot.shot, at: t, angle: shot.angle, top: pen.y)
                let blend = Motion.ease(t / 0.2) * (1 - Motion.ease((t - 0.8) / 0.2))
                eye = simd_mix(eye, pose.eye, SIMD3(repeating: blend))
                target = simd_mix(target, pose.target, SIMD3(repeating: blend))
                fieldOfView += (pose.fieldOfView - fieldOfView) * blend
            }
        }
        lens.fieldOfView = CGFloat(fieldOfView)
        camera.simdPosition = eye
        // Pin "up" to the world's, so the camera never rolls after looking straight down.
        camera.simdLook(at: target, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))

        let viewDistance = simd_distance(eye, target)
        scene.fogStartDistance = CGFloat(viewDistance * 0.9)
        scene.fogEndDistance = CGFloat(viewDistance * 2.2 + SpringPath.height)

        head.simdPosition = pen
        // Constant size on screen: scale with distance and with how wide the lens is.
        let lensWidth = tan(fieldOfView * .pi / 360) / tan(Self.fieldOfView * .pi / 360)
        head.simdScale = SIMD3(repeating: max(simd_distance(eye, pen), 0.3) * 0.01 * lensWidth)
    }

    private func shotPose(_ shot: CameraShot, at t: Float, angle: Float, top: Float)
        -> (eye: SIMD3<Float>, target: SIMD3<Float>, fieldOfView: Float) {
        switch shot {
        case .overview:
            // The whole spring so far, circled once.
            let middle = SIMD3<Float>(0, top / 2, 0)
            return (Motion.orbit(middle, distance: max(top, 2) * 1.1 + 2.6, yaw: angle + 2 * .pi * Motion.ease(t), pitch: 0.25),
                    middle, Self.fieldOfView)
        case .orbit:
            let level = SIMD3<Float>(0, top, 0)
            return (Motion.orbit(level, distance: 2.6, yaw: angle + 2 * .pi * Motion.ease(t), pitch: 0.2), level, Self.fieldOfView)
        case .topDown, .flythrough:
            // Straight down the axis from far away with a long lens, which flattens perspective:
            // every loop then stacks onto the flat drawing, and the near-miss loops land almost
            // exactly on turn 0's instead of shrinking into rings.
            let level = SIMD3<Float>(0, top, 0)
            // Within a third of a degree of vertical: any more tilt shears the stack.
            return (Motion.orbit(level, distance: 30, yaw: angle + 0.6 * t, pitch: 1.565), SIMD3(0, top * 0.5, 0), 8)
        }
    }
}
