import SwiftUI

/// A bitmap covering the square [-1/zoom, 1/zoom] of unit coordinates (y pointing down, like the
/// canvases) that strokes accumulate into, so long drawings never re-stroke their history every frame.
final class BakedLayer {
    /// Typical on-screen radius of the unit circle in points, used to match baked line widths to live ones.
    static let nominalRadius: CGFloat = 170

    let zoom: CGFloat
    private let context: CGContext
    private(set) var image: CGImage?

    /// `size` is the bitmap's side in pixels. Core Graphics fills each stroke's whole bounding box,
    /// so cost grows with the pixel count; 1024 already matches the screen at 1×.
    /// `highPrecision` stores 16-bit floats per channel instead of 8-bit integers. Very faint strokes
    /// (a million chords at 0.15% opacity each) round to nothing in 8 bits; in floats they add up.
    init(zoom: CGFloat, size: Int, highPrecision: Bool = false) {
        let bitmapInfo = highPrecision
            ? CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
                | CGBitmapInfo.byteOrder16Little.rawValue
            : CGImageAlphaInfo.premultipliedLast.rawValue
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: highPrecision ? 16 : 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: bitmapInfo) else {
            fatalError("Could not create the baked bitmap")
        }
        let half = CGFloat(size) / 2
        context.translateBy(x: half, y: half)
        context.scaleBy(x: half * zoom, y: -half * zoom)
        context.setBlendMode(.plusLighter)
        context.setLineCap(.round)
        self.zoom = zoom
        self.context = context
    }

    /// Strokes into the bitmap in unit coordinates, then refreshes `image`. The closure gets the
    /// unit-space width of one on-screen point at this layer's zoom.
    func draw(_ body: BakedLayers.Strokes) {
        body(context, 1 / (Self.nominalRadius * zoom))
        image = context.makeImage()
    }
}

/// Baked history at two resolutions: the whole drawing at 1×, plus a sharp copy of the zoomed-in
/// region that is re-rendered whenever a pinch settles. Stroking thousands of curves on the CPU is
/// slow, so it runs on a background queue and the new images come back on the main thread.
final class BakedLayers: @unchecked Sendable {
    /// Strokes in unit coordinates; `point` is the unit-space width of one on-screen point.
    typealias Strokes = @Sendable (CGContext, _ point: CGFloat) -> Void

    private static let baseSize = 1024
    private static let detailSize = 2048
    private let queue = DispatchQueue(label: "PiVisualizer.baked-layers", qos: .userInitiated)
    // Only touched on `queue`.
    private var base: BakedLayer?
    private var detail: BakedLayer?
    private var detailZoom: CGFloat = 1
    private var highPrecision = false
    // Only touched on the main thread; bumped by `clear()` so results of older work are dropped.
    private var generation = 0

    /// Adds strokes to every layer, then hands back the updated images.
    func draw(_ strokes: @escaping Strokes, completion: @escaping @MainActor (BakedImages) -> Void) {
        enqueue(completion) { [self] in
            if base == nil {
                base = BakedLayer(zoom: 1, size: Self.baseSize, highPrecision: highPrecision)
                if detailZoom > 1.05 {
                    detail = BakedLayer(zoom: detailZoom, size: Self.detailSize, highPrecision: highPrecision)
                }
            }
            base?.draw(strokes)
            detail?.draw(strokes)
        }
    }

    /// Re-renders the detail layer at `zoom` by replaying the whole history through `redraw`.
    func setDetailZoom(_ zoom: CGFloat, redraw: @escaping Strokes, completion: @escaping @MainActor (BakedImages) -> Void) {
        enqueue(completion) { [self] in
            detailZoom = zoom
            guard base != nil, zoom > 1.05 else {
                detail = nil
                return
            }
            let layer = BakedLayer(zoom: zoom, size: Self.detailSize, highPrecision: highPrecision)
            layer.draw(redraw)
            detail = layer
        }
    }

    /// Forgets the history but keeps the zoom, for a drawing that starts over. `highPrecision`
    /// chooses float bitmaps for the new drawing.
    func clear(highPrecision: Bool = false) {
        generation += 1
        queue.async { [self] in
            base = nil
            detail = nil
            self.highPrecision = highPrecision
        }
    }

    private func enqueue(_ completion: @escaping @MainActor (BakedImages) -> Void, work: @escaping () -> Void) {
        let started = generation
        queue.async { [self] in
            work()
            let images = BakedImages(base: base?.image, detail: detail?.image, detailZoom: detail?.zoom ?? 1)
            DispatchQueue.main.async {
                guard started == self.generation else { return }
                completion(images)
            }
        }
    }
}

struct BakedImages {
    var base: CGImage?
    var detail: CGImage?
    var detailZoom: CGFloat = 1
}

extension GraphicsContext {
    /// Draws baked history; call on a context already scaled to unit coordinates.
    func drawBaked(_ images: BakedImages) {
        guard let base = images.base else { return }
        let full = CGRect(x: -1, y: -1, width: 2, height: 2)
        guard let detail = images.detail else {
            draw(Image(decorative: base, scale: 1), in: full)
            return
        }
        let r = 1 / images.detailZoom
        let region = CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)
        // The detail layer replaces the base inside its region; drawing both there would double the glow.
        var outside = self
        outside.clip(to: Path(region), options: .inverse)
        outside.draw(Image(decorative: base, scale: 1), in: full)
        draw(Image(decorative: detail, scale: 1), in: region)
    }
}
