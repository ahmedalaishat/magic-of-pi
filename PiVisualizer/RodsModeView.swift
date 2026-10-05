import SwiftUI

/// A chain of spinning rods whose tip draws a trail; the style decides the rods' speeds and lengths.
struct RodsModeView: View {
    @Bindable var model: RodsModel
    @State private var editingFormula = false
    @State private var showingOptions = false

    var body: some View {
        VStack(spacing: 14) {
            ZoomableView(onZoomSettled: model.zoomSettled) { zoom in
                RodsDiagram(model: model, zoom: zoom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .recordingArea(square: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rotating rods, style \(model.style.rawValue)")
            .accessibilityValue(headerDetail)
            .overlay(alignment: .topLeading) { CounterBadge { headerDetail } }
            RodsReadout(model: model, onEditFormula: { editingFormula = true }).infoCard()
            ControlBar(isPlaying: model.isPlaying, onRestart: model.restart,
                       onTogglePlay: model.togglePlay, onOptions: { showingOptions = true })
        }
        .task(id: model.isPlaying) {
            await runFrameLoop(while: { model.isPlaying }, tick: model.tick(seconds:))
        }
        .sheet(isPresented: $editingFormula) {
            FormulaEditor(model: model)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingOptions) {
            OptionsSheet(topic: .rods, speed: $model.speed, speedRange: 0.01...20, hapticsOn: $model.hapticsOn,
                         makeWallpaper: { Wallpaper.shared.render(RodsDiagram(model: model, zoom: 1)) }) {
                RodsOptions(model: model)
            }
        }
    }

    private var headerDetail: String {
        if model.closesAfterOneTurn {
            return "\(Int((min(model.turns, 1) * 100).rounded()))% drawn"
        }
        let turns = String(format: "%.2f turns", model.turns)
        guard model.spotlightOn, let next = model.upcomingNearMiss else { return turns }
        return "\(turns) · next close call \(next)"
    }
}

/// The Rods settings: style, rod count, Spotlight and the formula.
private struct RodsOptions: View {
    @Bindable var model: RodsModel
    @State private var editingFormula = false

    var body: some View {
        Section("Style") {
            Picker("Style", selection: Binding(get: { model.style }, set: { model.setStyle($0) })) {
                ForEach(RodsModel.Style.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            if let range = model.rodCountRange {
                HStack {
                    Text("\(model.rodCount) rods").monospacedDigit().frame(width: 76, alignment: .leading)
                    Slider(value: Binding(get: { Double(model.rodCount) }, set: { model.setRodCount(Int($0.rounded())) }),
                           in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                }
            }
            if model.style == .formula {
                Button { editingFormula = true } label: { Label("Edit formula", systemImage: "function") }
            }
            if !model.closesAfterOneTurn {
                Toggle(isOn: $model.spotlightOn) { Label("Spotlight near-misses", systemImage: "scope") }
                    .tint(.purple)
            }
        }
        .sheet(isPresented: $editingFormula) {
            FormulaEditor(model: model).presentationDetents([.medium, .large])
        }
    }
}

struct RodsDiagram: View {
    let model: RodsModel
    let zoom: CGFloat

    var body: some View {
        // Read observed values here so SwiftUI redraws the canvas when they change.
        let theta = model.theta
        let baked = model.baked
        let chunks = model.pendingChunks + model.liveChunks()
        let joints = model.joints(at: theta)
        let opacity = model.trailOpacity
        let showGhost = model.style == .drawPi
        let camera = model.camera
        let passes = model.spotlightPasses(camera)
        let preview = model.spotlightPreview(camera)
        let start = model.pen(at: 0)

        Canvas { context, size in
            let radius = min(size.width, size.height) * 0.46
            let totalZoom = zoom * camera.zoom
            // Zoom by drawing larger, not by scaling a rendered image, so lines stay sharp.
            let scale = radius * totalZoom
            let toScreen = CGAffineTransform(translationX: size.width / 2, y: size.height / 2)
                .scaledBy(x: scale, y: scale)
                .translatedBy(x: -camera.center.x, y: -camera.center.y)
            var unit = context
            unit.concatenate(toScreen)
            func screen(_ p: CGPoint) -> CGPoint { p.applying(toScreen) }

            // Deep in the spotlight the baked trail is a blur, so it fades out in favour of the
            // finely sampled passes near the start point.
            let detail = min(max((totalZoom - 3) / 3, 0), 1)
            // Guides and orbits are big circles that break into visible straight segments at extreme zoom.
            let showGuides = totalZoom < 20

            if showGuides {
                unit.stroke(Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)),
                            with: .color(.white.opacity(0.08)), lineWidth: 1 / scale)
            }
            if showGhost {
                // The target shape, mirrored to screen orientation, so you can see how close the rods get.
                var ghost = Path()
                ghost.addLines(PiOutline.points.map { CGPoint(x: $0.x, y: -$0.y) })
                ghost.closeSubpath()
                unit.stroke(ghost, with: .color(.white.opacity(0.12)), lineWidth: 1 / scale)
            }

            if detail < 1 {
                var trail = unit
                trail.opacity = 1 - detail
                trail.drawBaked(baked)
                trail.blendMode = .plusLighter
                for chunk in chunks {
                    trail.stroke(chunk.path, with: .color(chunk.color.opacity(opacity)),
                                 style: StrokeStyle(lineWidth: RodsModel.trailWidth / scale, lineCap: .round))
                }
            }
            if detail > 0 {
                // Built in screen space with doubles: at 1000× single-precision unit coordinates wobble.
                var precise = context
                precise.opacity = detail
                precise.blendMode = .plusLighter
                for pass in passes {
                    var path = Path()
                    path.addLines(pass.points.map(screen))
                    precise.stroke(path, with: .color(pass.color), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                }
            }

            if camera.zoom > 1.5 {
                // Mark where the pen started, the point it keeps almost returning to.
                let s = screen(start)
                context.stroke(Path(ellipseIn: CGRect(x: s.x - 9, y: s.y - 9, width: 18, height: 18)),
                               with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                context.draw(Text("×\(totalZoom < 10 ? String(format: "%.1f", totalZoom) : Int(totalZoom).formatted())")
                                .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.8)),
                             at: CGPoint(x: size.width - 10, y: 10), anchor: .topTrailing)
            }

            // Each rod's orbit, centred on the joint it hangs from (skipped once too small to see).
            for i in 0..<(joints.count - 1) where showGuides {
                let r = hypot(joints[i + 1].x - joints[i].x, joints[i + 1].y - joints[i].y)
                guard r * scale > 3 else { continue }
                unit.stroke(Path(ellipseIn: CGRect(x: joints[i].x - r, y: joints[i].y - r, width: 2 * r, height: 2 * r)),
                            with: .color(.white.opacity(0.1)), lineWidth: 1 / scale)
            }

            // Rods are mapped to screen points in double precision: at a million times zoom,
            // the canvas's single-precision transform would make them jitter.
            var rods = Path()
            rods.addLines(joints.map(screen))
            // Thinner rods when there are many, so the chain stays readable.
            let width: CGFloat = joints.count > 12 ? 1.5 : 3
            // Dark outline keeps the rods visible once the trail fills in behind them.
            context.stroke(rods, with: .color(.black.opacity(0.7)),
                           style: StrokeStyle(lineWidth: width + 4, lineCap: .round, lineJoin: .round))
            context.stroke(rods, with: .color(.white.opacity(0.9)),
                           style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            // Dots and glow are drawn in screen points: tiny circles in the zoomed unit space
            // get flattened into polygons.
            if joints.count <= 12 {
                for point in joints.dropLast().map(screen) {
                    context.fill(Path(ellipseIn: CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7)),
                                 with: .color(.white))
                }
            }

            if preview.count > 1 {
                // Light gray preview of the pen's path ahead, so you can see it about to miss the start.
                var ahead = Path()
                ahead.addLines(preview.map(screen))
                context.stroke(ahead, with: .color(.white.opacity(0.4 * min((camera.zoom - 1.5) / 1.5, 1))),
                               style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            }

            // Glowing pen at the tip.
            let tip = screen(joints[joints.count - 1])
            context.fill(Path(ellipseIn: CGRect(x: tip.x - 14, y: tip.y - 14, width: 28, height: 28)),
                         with: .radialGradient(Gradient(colors: [model.color(at: theta), .clear]),
                                               center: tip, startRadius: 0, endRadius: 14))
        }
        // Rasterise on the GPU; Core Graphics on the main thread can't keep up with long trails.
        .drawingGroup()
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Style-specific facts about the drawing in progress.
struct RodsReadout: View {
    let model: RodsModel
    let onEditFormula: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            switch model.style {
            case .classic:
                convergent

            case .digits:
                Text("Rod speeds " + model.rods.map { String(format: "%+.0f", $0.speed) }.joined(separator: " "))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

            case .drawPi:
                Text("\(model.rodCount) circles · more rods, sharper π")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(model.color(at: model.theta))

            case .formula:
                Button(action: onEditFormula) {
                    HStack(spacing: 10) {
                        FormulaText(rods: model.formulaRods)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(Rectangle().stroke(.white.opacity(0.8), lineWidth: 1))
                }
                .foregroundStyle(.white)
            }
        }
        .frame(height: 30)
    }

    @ViewBuilder private var convergent: some View {
        Group {
            if let fraction = model.latestConvergent {
                Text("Nearly closed at \(fraction.turns) turns · π ≈ \(fraction.numerator)/\(fraction.turns) = "
                     + String(format: "%.7f", Double(fraction.numerator) / Double(fraction.turns)))
                    .foregroundStyle(model.color(at: Double(fraction.turns) * 2 * .pi))
            } else {
                Text("Watch for the near-miss after 7 turns")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote.weight(.medium))
        .contentTransition(.opacity)
        .animation(.easeInOut, value: model.latestConvergent?.turns)
    }
}

/// The rods written as z(θ) = Σ length·e^{(speed·θ)i}, with the exponents raised.
struct FormulaText: View {
    let rods: [RodsModel.FormulaRod]

    var body: some View {
        rods.enumerated().reduce(Text("z(θ) = ")) { text, item in
            let (index, rod) = item
            let exponent = Text(Self.exponent(rod))
                .font(.system(size: 12, design: .serif).italic())
                .baselineOffset(9)
            return Text("\(text)\(index > 0 ? " + " : "")\(Self.coefficient(rod.length))e\(exponent)")
        }
        .font(.system(size: 19, design: .serif).italic())
    }

    /// 1 is omitted and a leading zero dropped, as in ".9".
    private static func coefficient(_ length: Double) -> String {
        guard abs(length - 1) > 0.001 else { return "" }
        let text = String(format: "%g", (length * 100).rounded() / 100)
        return text.hasPrefix("0.") ? String(text.dropFirst()) : text
    }

    private static func exponent(_ rod: RodsModel.FormulaRod) -> String {
        if rod.multiplier == 0 { return "0" }
        if rod.multiplier == 1, !rod.timesPi { return "θi" }
        let magnitude = abs(rod.multiplier) == 1 && rod.timesPi ? "" : String(format: "%g", abs(rod.multiplier))
        return "(\(rod.multiplier < 0 ? "−" : "")\(magnitude)\(rod.timesPi ? "π" : "")θ)i"
    }
}

/// Edit each rod's length and speed; every change restarts the drawing.
struct FormulaEditor: View {
    @Bindable var model: RodsModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    FormulaText(rods: model.formulaRods)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity)
                }
                ForEach($model.formulaRods) { $rod in
                    Section("Rod \((model.formulaRods.firstIndex { $0.id == rod.id } ?? 0) + 1)") {
                        HStack {
                            Text("Length")
                            Slider(value: $rod.length, in: 0.1...1, step: 0.05)
                            Text(String(format: "%.2f", rod.length)).monospacedDigit()
                        }
                        Stepper(value: $rod.multiplier, in: -6...6, step: 0.5) {
                            Text("Speed \(String(format: "%g", rod.multiplier))\(rod.timesPi ? "π" : "")")
                                .monospacedDigit()
                        }
                        Toggle("Times π", isOn: $rod.timesPi)
                        if model.formulaRods.count > 1 {
                            Button("Remove rod", role: .destructive) {
                                model.formulaRods.removeAll { $0.id == rod.id }
                            }
                        }
                    }
                }
                Section {
                    Button("Add rod") {
                        model.formulaRods.append(RodsModel.FormulaRod(length: 0.5, multiplier: 3, timesPi: false))
                    }
                    .disabled(model.formulaRods.count >= RodsModel.maxFormulaRods)
                    Button("Reset to e^{θi} + .9e^{(−πθ)i} + .8e^{(2πθ)i}") {
                        model.formulaRods = RodsModel.formulaPreset
                    }
                }
            }
            .navigationTitle("Formula")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
