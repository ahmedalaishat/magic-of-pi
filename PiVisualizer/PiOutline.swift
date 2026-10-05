import CoreText
import CoreGraphics

/// The outline of a "π" glyph, sampled evenly and broken into rotating circles (a Fourier series).
enum PiOutline {
    private static let sampleCount = 1024

    /// Evenly spaced points around the glyph's outline, centred at the origin, fitting radius 0.85, y up.
    static let points: [CGPoint] = {
        let font = CTFontCreateWithName("TimesNewRomanPS-ItalicMT" as CFString, 100, nil)
        var character: UniChar = 0x03C0
        var glyph = CGGlyph()
        guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1),
              let path = CTFontCreatePathForGlyph(font, glyph, nil) else {
            fatalError("No π glyph in the outline font")
        }
        return normalized(resample(flatten(path), count: sampleCount))
    }()

    /// Fourier terms of the outline, largest first: point(θ) = Σ length·e^{i(speed·θ + phase)}.
    static let terms: [(length: Double, speed: Double, phase: Double)] = {
        let n = points.count
        let cosTable = (0..<n).map { cos(2 * .pi * Double($0) / Double(n)) }
        let sinTable = (0..<n).map { sin(2 * .pi * Double($0) / Double(n)) }
        return (-(n / 2) + 1...(n / 2)).map { k -> (length: Double, speed: Double, phase: Double) in
            var re = 0.0, im = 0.0
            for (j, p) in points.enumerated() {
                // Multiply by e^{-i·2πkj/n}, using the table index (k·j mod n).
                let index = ((k * j) % n + n) % n
                re += Double(p.x) * cosTable[index] + Double(p.y) * sinTable[index]
                im += Double(p.y) * cosTable[index] - Double(p.x) * sinTable[index]
            }
            re /= Double(n)
            im /= Double(n)
            return (hypot(re, im), Double(k), atan2(im, re))
        }
        .sorted { $0.length > $1.length }
    }()

    /// Polyline of the path; curves are split into short straight pieces. Contours are joined end to end.
    private static func flatten(_ path: CGPath) -> [CGPoint] {
        var result: [CGPoint] = []
        var current = CGPoint.zero
        let pieces = 12
        path.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint, .addLineToPoint:
                current = e.points[0]
                result.append(current)
            case .addQuadCurveToPoint:
                let (c, end) = (e.points[0], e.points[1])
                for step in 1...pieces {
                    let t = CGFloat(step) / CGFloat(pieces), u = 1 - t
                    result.append(CGPoint(x: u * u * current.x + 2 * u * t * c.x + t * t * end.x,
                                          y: u * u * current.y + 2 * u * t * c.y + t * t * end.y))
                }
                current = end
            case .addCurveToPoint:
                let (c1, c2, end) = (e.points[0], e.points[1], e.points[2])
                for step in 1...pieces {
                    let t = CGFloat(step) / CGFloat(pieces), u = 1 - t
                    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
                    result.append(CGPoint(x: a * current.x + b * c1.x + c * c2.x + d * end.x,
                                          y: a * current.y + b * c1.y + c * c2.y + d * end.y))
                }
                current = end
            case .closeSubpath:
                break
            @unknown default:
                break
            }
        }
        return result
    }

    /// `count` points spaced evenly by arc length around the closed polyline.
    private static func resample(_ points: [CGPoint], count: Int) -> [CGPoint] {
        let closed = points + [points[0]]
        var cumulative = [0.0]
        for i in 1..<closed.count {
            cumulative.append(cumulative[i - 1] + hypot(closed[i].x - closed[i - 1].x, closed[i].y - closed[i - 1].y))
        }
        let total = cumulative[cumulative.count - 1]
        var result: [CGPoint] = []
        var segment = 1
        for i in 0..<count {
            let target = total * Double(i) / Double(count)
            while cumulative[segment] < target { segment += 1 }
            let span = cumulative[segment] - cumulative[segment - 1]
            let t = span > 0 ? (target - cumulative[segment - 1]) / span : 0
            let a = closed[segment - 1], b = closed[segment]
            result.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        }
        return result
    }

    private static func normalized(_ points: [CGPoint]) -> [CGPoint] {
        let xs = points.map(\.x), ys = points.map(\.y)
        let center = CGPoint(x: (xs.min()! + xs.max()!) / 2, y: (ys.min()! + ys.max()!) / 2)
        let reach = points.map { hypot($0.x - center.x, $0.y - center.y) }.max()!
        let scale = 0.85 / reach
        return points.map { CGPoint(x: ($0.x - center.x) * scale, y: ($0.y - center.y) * scale) }
    }
}
