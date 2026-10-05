import SwiftUI

/// Opening animation: spinning circles (the Fourier rods of the Draw π style) trace the π glyph,
/// it glows, the digits stream in, and the whole thing hands over to the app. Tap to skip.
struct SplashView: View {
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var finished = false

    private static let digits = "3.14159 26535 89793 23846 26433"

    // Timeline, in seconds.
    private static let drawEnd = 2.4
    private static let glowEnd = 3.0
    private static let digitsEnd = 3.9
    private static let total = 4.5

    var body: some View {
        TimelineView(.animation(paused: finished)) { timeline in
            let time = reduceMotion ? Self.drawEnd + 0.1 : timeline.date.timeIntervalSince(start)
            let draw = Self.ease(time / Self.drawEnd)
            let glow = Self.ease((time - Self.drawEnd) / (Self.glowEnd - Self.drawEnd))
            let typed = Self.ease((time - Self.glowEnd + 0.4) / (Self.digitsEnd - Self.glowEnd + 0.4))
            let fade = Self.ease((time - Self.digitsEnd) / (Self.total - Self.digitsEnd))

            VStack(spacing: 28) {
                Canvas { context, size in
                    drawGlyph(in: &context, size: size, progress: draw, glow: glow)
                }
                .aspectRatio(1, contentMode: .fit)
                .padding(.horizontal, 40)

                Text(Self.digits.prefix(Int((Double(Self.digits.count) * typed).rounded())))
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(height: 30)
            }
            .scaleEffect(1 + 0.08 * fade)
            .opacity(1 - fade)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(1 - fade).ignoresSafeArea())
            .onChange(of: time >= Self.total) { _, done in if done { finish() } }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: finish)
        .onAppear {
            start = Date()
            // With Reduce Motion the glyph appears already drawn; hold it briefly, then continue.
            if reduceMotion {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: finish)
            }
        }
        .accessibilityLabel("π")
        .accessibilityAddTraits(.isImage)
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }

    private func drawGlyph(in context: inout GraphicsContext, size: CGSize, progress: Double, glow: Double) {
        let scale = min(size.width, size.height) / 2
        func screen(_ p: CGPoint) -> CGPoint {
            CGPoint(x: size.width / 2 + p.x * scale, y: size.height / 2 + p.y * scale)
        }

        let drawn = Int(progress * Double(PiGlyph.sampleCount))
        if drawn > 0 {
            var path = Path()
            path.addLines(PiGlyph.trail[0...drawn].map(screen))
            let colors = Gradient(colors: (0...6).map { Color(hue: 0.55 + 0.45 * Double($0) / 6, saturation: 0.7, brightness: 1) })
            let shading = GraphicsContext.Shading.linearGradient(colors, startPoint: .zero,
                                                                  endPoint: CGPoint(x: size.width, y: size.height))
            // Soft halo underneath, brightening once the glyph is complete.
            context.drawLayer { halo in
                halo.addFilter(.blur(radius: 10 + 8 * glow))
                halo.opacity = 0.55 + 0.45 * glow
                halo.stroke(path, with: shading, style: StrokeStyle(lineWidth: 6 + 6 * glow, lineCap: .round, lineJoin: .round))
            }
            context.stroke(path, with: shading, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }

        // The rods themselves, fading away once their work is done.
        let rodOpacity = 1 - glow
        guard rodOpacity > 0.01, progress < 1 || glow < 1 else { return }
        let theta = 2 * Double.pi * progress
        var joint = CGPoint.zero
        var chain = Path()
        chain.move(to: screen(joint))
        for rod in PiGlyph.rods {
            let angle = rod.speed * theta + rod.phase
            let next = CGPoint(x: joint.x + rod.length * cos(angle), y: joint.y - rod.length * sin(angle))
            let r = rod.length * scale
            if r > 2 {
                let c = screen(joint)
                context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                               with: .color(.white.opacity(0.12 * rodOpacity)), lineWidth: 1)
            }
            chain.addLine(to: screen(next))
            joint = next
        }
        context.stroke(chain, with: .color(.white.opacity(0.75 * rodOpacity)),
                       style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        let tip = screen(joint)
        context.fill(Path(ellipseIn: CGRect(x: tip.x - 4, y: tip.y - 4, width: 8, height: 8)),
                     with: .color(.white.opacity(rodOpacity)))
    }

    private static func ease(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }
}

/// The π glyph drawn by its 60 largest Fourier circles: shared by the splash and the home screen.
enum PiGlyph {
    static let rods = Array(PiOutline.terms.prefix(60))
    static let sampleCount = 720
    /// The pen's path over one turn, in unit coordinates (y down, so π stands upright).
    static let trail: [CGPoint] = (0...sampleCount).map { pen(at: 2 * .pi * Double($0) / Double(sampleCount)) }

    static func pen(at theta: Double) -> CGPoint {
        var x = 0.0, y = 0.0
        for rod in rods {
            let angle = rod.speed * theta + rod.phase
            x += rod.length * cos(angle)
            y -= rod.length * sin(angle)
        }
        return CGPoint(x: x, y: y)
    }

    /// The origin, then the end of each rod, at angle θ.
    static func joints(at theta: Double) -> [CGPoint] {
        var joint = CGPoint.zero
        var points = [joint]
        for rod in rods {
            let angle = rod.speed * theta + rod.phase
            joint = CGPoint(x: joint.x + rod.length * cos(angle), y: joint.y - rod.length * sin(angle))
            points.append(joint)
        }
        return points
    }
}
