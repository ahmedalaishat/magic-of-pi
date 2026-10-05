import SwiftUI

/// Geometry of the chord diagram on a unit circle centred at the origin.
/// Each digit owns a tenth of the ring; chord i leaves digit i's arc and lands on digit i+1's arc,
/// sliding along each arc as i grows so the chords fan out instead of stacking.
enum ChordLayout {
    static let segment = 2 * Double.pi / 10
    static let gap = segment * 0.12

    static func color(_ digit: Int) -> Color {
        Color(hue: (Double(digit) / 10 + 0.55).truncatingRemainder(dividingBy: 1), saturation: 0.75, brightness: 1)
    }

    /// Angle of a point on `digit`'s arc; `fraction` runs 0...1 from the arc's start to its end.
    static func angle(digit: Int, fraction: Double) -> Double {
        -Double.pi / 2 + Double(digit) * segment + gap / 2 + fraction * (segment - gap)
    }

    static func point(angle: Double, radius: Double = 1) -> CGPoint {
        CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
    }

    static func chord(from a: Int, at fa: Double, to b: Int, at fb: Double) -> Path {
        let (p0, control, p1) = chordPoints(from: a, at: fa, to: b, at: fb)
        var path = Path()
        path.move(to: p0)
        path.addQuadCurve(to: p1, control: control)
        return path
    }

    /// The same chord cut into `count` consecutive curves. Core Graphics fills each stroke's whole
    /// bounding box, so short pieces are far cheaper to rasterise than one long curve.
    static func chordPieces(from a: Int, at fa: Double, to b: Int, at fb: Double, count: Int) -> [CGPath] {
        let (p0, c, p1) = chordPoints(from: a, at: fa, to: b, at: fb)
        func at(_ t: CGFloat) -> CGPoint {
            let u = 1 - t
            return CGPoint(x: u * u * p0.x + 2 * u * t * c.x + t * t * p1.x,
                           y: u * u * p0.y + 2 * u * t * c.y + t * t * p1.y)
        }
        func slope(_ t: CGFloat) -> CGPoint {
            CGPoint(x: 2 * (1 - t) * (c.x - p0.x) + 2 * t * (p1.x - c.x),
                    y: 2 * (1 - t) * (c.y - p0.y) + 2 * t * (p1.y - c.y))
        }
        return (0..<count).map { k in
            let t0 = CGFloat(k) / CGFloat(count), t1 = CGFloat(k + 1) / CGFloat(count)
            let start = at(t0), d = slope(t0), half = (t1 - t0) / 2
            let path = CGMutablePath()
            path.move(to: start)
            // A quadratic's sub-curve on [t0, t1] has its control point where the end tangents meet.
            path.addQuadCurve(to: at(t1), control: CGPoint(x: start.x + d.x * half, y: start.y + d.y * half))
            return path
        }
    }

    private static func chordPoints(from a: Int, at fa: Double, to b: Int, at fb: Double) -> (CGPoint, CGPoint, CGPoint) {
        let p0 = point(angle: angle(digit: a, fraction: fa))
        let p1 = point(angle: angle(digit: b, fraction: fb))
        // Pull the curve towards the centre; chords between nearby arcs bend less.
        let control = CGPoint(x: (p0.x + p1.x) * 0.12, y: (p0.y + p1.y) * 0.12)
        return (p0, control, p1)
    }

    static func arc(digit: Int, radius: Double) -> Path {
        var path = Path()
        path.addArc(center: .zero, radius: radius,
                    startAngle: .radians(angle(digit: digit, fraction: 0)),
                    endAngle: .radians(angle(digit: digit, fraction: 1)),
                    clockwise: false)
        return path
    }
}
