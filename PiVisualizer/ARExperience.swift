import ARKit
import SceneKit
import SwiftUI

/// A 3D shape (the walk or the spring) to place in the room through the camera.
struct ARShape {
    let points: [SIMD3<Float>]
    let colors: [SIMD4<Float>]
    /// Size, in metres, of the shape's largest dimension once placed.
    let size: Float
}

/// Camera view: find a surface, tap to place the shape, pinch to resize, tap again to move it.
struct ARExperienceView: View {
    let shape: ARShape
    @Environment(\.dismiss) private var dismiss
    @State private var placed = false

    var body: some View {
        ZStack(alignment: .top) {
            if ARWorldTrackingConfiguration.isSupported {
                ARSceneView(shape: shape, placed: $placed).ignoresSafeArea()
            } else {
                Text("AR isn't supported on this device.").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(alignment: .top) {
                Text(placed ? "Pinch to resize · tap to move" : "Move your phone to find a table or the floor, then tap to place")
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.headline).padding(12)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Close")
            }
            .padding(16)
        }
        .background(Color.black)
    }
}

private struct ARSceneView: UIViewRepresentable {
    let shape: ARShape
    @Binding var placed: Bool

    func makeCoordinator() -> Coordinator { Coordinator(shape: shape, placed: $placed) }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.automaticallyUpdatesLighting = false
        view.antialiasingMode = .multisampling4X
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        view.session.run(configuration)
        context.coordinator.view = view
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:))))
        view.addGestureRecognizer(UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:))))
        return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) {}

    static func dismantleUIView(_ view: ARSCNView, coordinator: Coordinator) {
        view.session.pause()
    }

    final class Coordinator: NSObject {
        weak var view: ARSCNView?
        private let anchor = SCNNode()
        private var placed: Binding<Bool>

        init(shape: ARShape, placed: Binding<Bool>) {
            self.placed = placed
            super.init()
            anchor.addChildNode(Self.makeNode(shape))
        }

        @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard let view else { return }
            let point = gesture.location(in: view)
            guard let query = view.raycastQuery(from: point, allowing: .estimatedPlane, alignment: .horizontal),
                  let hit = view.session.raycast(query).first else { return }
            anchor.simdTransform = hit.worldTransform
            if anchor.parent == nil {
                view.scene.rootNode.addChildNode(anchor)
                placed.wrappedValue = true
            }
        }

        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            let scale = min(max(anchor.simdScale.x * Float(gesture.scale), 0.2), 6)
            anchor.simdScale = SIMD3(repeating: scale)
            gesture.scale = 1
        }

        /// The shape as glowing lines, sized to `shape.size`, standing on the surface and spinning slowly.
        private static func makeNode(_ shape: ARShape) -> SCNNode {
            let points = shape.points
            var lower = points.first ?? .zero, upper = lower
            for p in points { lower = simd_min(lower, p); upper = simd_max(upper, p) }
            let extent = upper - lower
            let scale = shape.size / max(extent.x, extent.y, extent.z, 0.001)
            let center = SIMD3((lower.x + upper.x) / 2, lower.y, (lower.z + upper.z) / 2)

            let count = points.count
            let vertices = SCNGeometrySource(vertices: points.map { SCNVector3(($0 - center) * scale) })
            let colorSource = SCNGeometrySource(
                data: shape.colors.withUnsafeBufferPointer { Data(buffer: $0) },
                semantic: .color, vectorCount: count, usesFloatComponents: true,
                componentsPerVector: 4, bytesPerComponent: MemoryLayout<Float>.size,
                dataOffset: 0, dataStride: MemoryLayout<SIMD4<Float>>.stride)
            var indices = [UInt32](repeating: 0, count: max(count - 1, 0) * 2)
            for i in 0..<max(count - 1, 0) {
                indices[2 * i] = UInt32(i)
                indices[2 * i + 1] = UInt32(i + 1)
            }
            let geometry = SCNGeometry(sources: [vertices, colorSource],
                                       elements: [SCNGeometryElement(indices: indices, primitiveType: .line)])
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = UIColor.white
            geometry.materials = [material]
            let node = SCNNode(geometry: geometry)
            node.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 40)))
            return node
        }
    }
}

extension ARShape {
    /// Colour drifting from cyan through violet to pink along the shape, like the 3D views.
    static func gradient(count: Int) -> [SIMD4<Float>] {
        (0..<count).map { i in
            let t = Float(i) / Float(max(count - 1, 1))
            let hue = (0.5 + 0.45 * t).truncatingRemainder(dividingBy: 1)
            let h = hue * 6, sector = Int(h) % 6, f = h - Float(Int(h))
            let s: Float = 0.7, p = 1 - s, q = 1 - s * f, u = 1 - s * (1 - f)
            let (r, g, b): (Float, Float, Float) = switch sector {
            case 0: (1, u, p)
            case 1: (q, 1, p)
            case 2: (p, 1, u)
            case 3: (p, q, 1)
            case 4: (u, p, 1)
            default: (1, p, q)
            }
            return SIMD4(r, g, b, 1)
        }
    }
}
