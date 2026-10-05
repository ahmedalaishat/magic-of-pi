import SwiftUI

/// The starting screen: a live π drawn by rods, a "did you know" card, the four visualizations,
/// and the birthday search.
struct HomeView: View {
    let onOpen: (ContentView.Mode) -> Void
    let onFindBirthday: () -> Void
    @State private var visible = true

    var body: some View {
        ZStack {
            DriftingDigits(animating: visible)
            VStack(spacing: 18) {
                Text("MAGIC OF π")
                    .font(.system(size: 12, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                LivePi(animating: visible)
                    .frame(height: 220)
                    .accessibilityLabel("π, drawn by spinning circles")
                Text("3.14159 26535 89793 23846 26433…")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.top, -10)
                FactCard()
                modeGrid
                Spacer(minLength: 0)
                Button(action: onFindBirthday) {
                    Label("Find your birthday in π", systemImage: "magnifyingglass")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color(red: 0.49, green: 0.23, blue: 0.93), in: Capsule())
                }
                .foregroundStyle(.white)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .background(Color.black.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { visible = true }
        .onDisappear { visible = false }
    }

    private var modeGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ModeTile(mode: .chords, subtitle: "Digits joined in a circle", onOpen: onOpen)
            ModeTile(mode: .rods, subtitle: "The loop that never closes", onOpen: onOpen)
            ModeTile(mode: .walk, subtitle: "Each digit a step in space", onOpen: onOpen)
            ModeTile(mode: .spring, subtitle: "Turns stacked in time", onOpen: onOpen)
        }
    }
}

/// The rods slowly orbiting, their pen tracing the π glyph over and over.
private struct LivePi: View {
    let animating: Bool
    /// Seconds for the pen to trace the whole glyph once.
    private static let period = 14.0
    private static let colors = Gradient(colors: [Color(red: 0.35, green: 0.78, blue: 0.98),
                                                  Color(red: 0.66, green: 0.33, blue: 0.97),
                                                  Color(red: 0.96, green: 0.45, blue: 0.71)])
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: !animating || reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period) / Self.period
            Canvas { context, size in
                let scale = min(size.width, size.height) / 2
                func screen(_ p: CGPoint) -> CGPoint {
                    CGPoint(x: size.width / 2 + p.x * scale, y: size.height / 2 + p.y * scale)
                }
                let shading = GraphicsContext.Shading.linearGradient(
                    Self.colors, startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height))

                // The whole glyph, faint, so π is always readable; the moving trail is the bright part.
                var whole = Path()
                whole.addLines(PiGlyph.trail.map(screen))
                var faint = context
                faint.opacity = reduceMotion ? 1 : 0.28
                faint.stroke(whole, with: shading, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                // A glowing trail behind the pen, fading towards its tail.
                let count = PiGlyph.sampleCount
                let head = reduceMotion ? count : Int(t * Double(count))
                let length = count * 2 / 5
                let pieces = 12
                for k in 0..<pieces {
                    let from = head - length + k * length / pieces, to = from + length / pieces + 1
                    let points = (from...to).map { PiGlyph.trail[(($0 % count) + count) % count] }
                    var piece = Path()
                    piece.addLines(points.map(screen))
                    let strength = Double(k + 1) / Double(pieces)
                    context.drawLayer { glow in
                        glow.addFilter(.blur(radius: 8))
                        glow.opacity = 0.7 * strength
                        glow.stroke(piece, with: shading, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    }
                    var crisp = context
                    crisp.opacity = strength
                    crisp.stroke(piece, with: shading, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                }

                // The rods and their orbits.
                guard !reduceMotion else { return }
                let joints = PiGlyph.joints(at: 2 * .pi * t)
                for i in 0..<(joints.count - 1) {
                    let r = hypot(joints[i + 1].x - joints[i].x, joints[i + 1].y - joints[i].y) * scale
                    guard r > 3 else { continue }
                    let c = screen(joints[i])
                    context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                                   with: .color(.white.opacity(0.07)), lineWidth: 1)
                }
                var chain = Path()
                chain.addLines(joints.map(screen))
                context.stroke(chain, with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
                let tip = screen(joints[joints.count - 1])
                context.fill(Path(ellipseIn: CGRect(x: tip.x - 4, y: tip.y - 4, width: 8, height: 8)), with: .color(.white))
            }
        }
    }
}

/// π's digits drifting slowly upward behind the hero. Two identical copies are stacked and the
/// drift wraps by exactly one copy's height, so the loop is seamless and the screen never empties.
private struct DriftingDigits: View {
    let animating: Bool
    private static let text = PiDigits.all.prefix(2_400).map(String.init).joined()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copyHeight: CGFloat = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !animating || reduceMotion)) { timeline in
            GeometryReader { geometry in
                let drift = CGFloat(timeline.date.timeIntervalSinceReferenceDate * 6)
                let offset = copyHeight > 0 ? drift.truncatingRemainder(dividingBy: copyHeight) : 0
                VStack(spacing: 0) {
                    digits
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { copyHeight = $0 }
                    digits
                }
                .frame(width: geometry.size.width + 40)
                .offset(x: -20, y: -offset)
            }
            .clipped()
            // Clear behind the hero and the card, fading out behind the tiles and buttons.
            .mask(LinearGradient(stops: [.init(color: .white, location: 0), .init(color: .white, location: 0.5),
                                         .init(color: .clear, location: 0.8)], startPoint: .top, endPoint: .bottom))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var digits: some View {
        Text(Self.text)
            .font(.system(size: 15, design: .monospaced))
            .tracking(3)
            .lineSpacing(6)
            .foregroundStyle(.white.opacity(0.09))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// "Did you know": one fact at a time, advancing on its own.
private struct FactCard: View {
    private static let facts: [(title: String, body: String)] = [
        ("π never repeats", "Its digits run forever with no pattern. Ten million of them are inside this app."),
        ("355 ÷ 113 = 3.1415929…", "Zu Chongzhi found this fraction 1,500 years ago. It is right to six decimal places."),
        ("Your birthday is in π", "Any six-digit date turns up in the first ten million digits, 99.995% of the time."),
        ("Six 9s at digit 762", "999999 appears early in π. It is called the Feynman point."),
        ("The loop never closes", "Two rods, one spinning π times faster, never meet their start again, because π is not a fraction."),
    ]
    @State private var index = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("DID YOU KNOW")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color(red: 0.79, green: 0.65, blue: 1))
                Spacer()
                Button { go(index - 1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 30) }
                    .accessibilityLabel("Previous fact")
                Button { go(index + 1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 30) }
                    .accessibilityLabel("Next fact")
            }
            .foregroundStyle(.white)
            // A paging view: the fact follows the finger and slides; buttons, dots and the timer
            // slide it too.
            TabView(selection: $index) {
                ForEach(Self.facts.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Self.facts[i].title)
                            .font(.system(size: 25, design: .serif))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(Self.facts[i].body)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 96)
            HStack(spacing: 6) {
                ForEach(Self.facts.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == index ? Color(red: 0.79, green: 0.65, blue: 1) : .white.opacity(0.22))
                        .frame(width: i == index ? 22 : 8, height: 8)
                        .onTapGesture { go(i) }
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.spring(duration: 0.35), value: index)
            .accessibilityHidden(true)
        }
        .padding(18)
        // Raised: a lighter surface, an edge catching light at the top, and a soft violet glow below.
        .background(
            LinearGradient(colors: [Color(white: 0.14), Color(white: 0.08)], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1))
        .shadow(color: Color(red: 0.49, green: 0.23, blue: 0.93).opacity(0.35), radius: 22, y: 10)
        .shadow(color: .black.opacity(0.8), radius: 6, y: 4)
        // Advance on its own; any tap or swipe restarts the wait.
        .task(id: index) {
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { go(index + 1) }
        }
    }

    private func go(_ i: Int) {
        withAnimation(.spring(duration: 0.45)) { index = (i + Self.facts.count) % Self.facts.count }
    }
}

/// A visualization's tile on the home screen.
private struct ModeTile: View {
    let mode: ContentView.Mode
    let subtitle: String
    let onOpen: (ContentView.Mode) -> Void

    var body: some View {
        Button { onOpen(mode) } label: {
            VStack(alignment: .leading, spacing: 8) {
                ModeIcon(mode: mode).frame(width: 40, height: 40)
                Text(mode.rawValue).font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(white: 0.07), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.08)))
        }
        .foregroundStyle(.white)
    }
}

/// Small line drawings of each visualization.
private struct ModeIcon: View {
    let mode: ContentView.Mode
    private static let cyan = Color(red: 0.35, green: 0.78, blue: 0.98)
    private static let violet = Color(red: 0.66, green: 0.33, blue: 0.97)
    private static let pink = Color(red: 0.96, green: 0.45, blue: 0.71)

    var body: some View {
        Canvas { context, size in
            let s = size.width / 44
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            let line = StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
            let ring = Path(ellipseIn: CGRect(x: 3 * s, y: 3 * s, width: 38 * s, height: 38 * s))
            switch mode {
            case .chords:
                context.stroke(ring, with: .color(.white.opacity(0.2)), style: line)
                for (a, c, b, color) in [(p(22, 3), p(24, 22), p(39, 28), Self.cyan), (p(8, 34), p(22, 22), p(30, 5), Self.violet),
                                         (p(4, 18), p(22, 24), p(36, 34), Self.pink)] {
                    var path = Path()
                    path.move(to: a)
                    path.addQuadCurve(to: b, control: c)
                    context.stroke(path, with: .color(color), style: line)
                }
            case .rods:
                context.stroke(ring, with: .color(.white.opacity(0.2)), style: line)
                context.stroke(Path(ellipseIn: CGRect(x: 19 * s, y: 7 * s, width: 18 * s, height: 18 * s)), with: .color(Self.violet), style: line)
                context.stroke(Path(ellipseIn: CGRect(x: 7 * s, y: 18 * s, width: 18 * s, height: 18 * s)), with: .color(Self.cyan), style: line)
                var chain = Path()
                chain.addLines([p(22, 22), p(31, 10), p(38, 18)])
                context.stroke(chain, with: .color(.white), style: line)
            case .walk:
                var first = Path(), second = Path()
                first.addLines([p(6, 30), p(11, 24), p(9, 18), p(15, 15), p(19, 21), p(24, 17), p(22, 10), p(29, 8), p(32, 15), p(38, 13)])
                second.addLines([p(38, 13), p(35, 22), p(39, 28), p(32, 33), p(27, 29)])
                context.stroke(first, with: .color(Self.cyan), style: line)
                context.stroke(second, with: .color(Self.pink), style: line)
            case .spring:
                for (y, color) in [(34.0, Self.cyan), (26, Self.violet), (18, Color(red: 0.75, green: 0.52, blue: 0.99)), (10, Self.pink)] {
                    context.stroke(Path(ellipseIn: CGRect(x: 7 * s, y: (y - 5) * s, width: 30 * s, height: 10 * s)),
                                   with: .color(color), style: line)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
