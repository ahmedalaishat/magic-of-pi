import SwiftUI

/// Digits 0–9 around a ring; each consecutive pair of digits in π draws a chord between them.
struct ChordModeView: View {
    @Bindable var model: PiChordModel
    @State private var showingOptions = false

    var body: some View {
        VStack(spacing: 14) {
            ZoomableView(onTap: { if !model.isPlaying { model.step() } }, onZoomSettled: model.zoomSettled) { zoom in
                ChordDiagram(model: model, zoom: zoom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .recordingArea(square: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Chord diagram of \(model.constant.rawValue)'s digits")
            .accessibilityValue("\((model.completed + 1).formatted()) of \(model.digitCount.formatted()) digits drawn")
            .accessibilityHint("Each pair of neighbouring digits draws a chord between them.")
            .overlay(alignment: .topLeading) {
                CounterBadge {
                    if model.fillingIn { return "Drawing \(model.completed.formatted()) chords…" }
                    if let highlight = model.highlight { return "Your number at digit \(highlight.lowerBound.formatted())" }
                    return "\((model.completed + 1).formatted()) / \(model.digitCount.formatted()) digits"
                }
            }
            DigitStrip(model: model).infoCard()
            ControlBar(isPlaying: model.isPlaying, onRestart: model.restart,
                       onTogglePlay: model.togglePlay, onOptions: { showingOptions = true })
        }
        .task(id: model.isPlaying) {
            await runFrameLoop(while: { model.isPlaying }, tick: model.tick(seconds:))
        }
        .sheet(isPresented: $showingOptions) {
            OptionsSheet(topic: .chords, speed: $model.speed, speedRange: 2...50_000, hapticsOn: $model.hapticsOn,
                         makeWallpaper: { Wallpaper.shared.render(ChordDiagram(model: model, zoom: 1)) }) {
                Section {
                    Picker("Number", selection: Binding(get: { model.constant }, set: { model.setConstant($0) })) {
                        ForEach(Constant.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Number")
                } footer: {
                    Text("Compare π with e, √2 and the golden ratio φ. Digit by digit all four look equally random; the magic of π is in its geometry.")
                }
                Section("Digits") {
                    Picker("Digits", selection: Binding(get: { model.digitCount }, set: { model.setDigitCount($0) })) {
                        ForEach(PiChordModel.countOptions, id: \.self) {
                            Text($0.formatted(.number.notation(.compactName))).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }
}

struct ChordDiagram: View {
    let model: PiChordModel
    let zoom: CGFloat

    var body: some View {
        // Read observed values here so SwiftUI redraws the canvas when they change.
        let paths = model.chordPaths
        let pending = model.pendingPaths
        let baked = model.baked
        let live = model.liveChord
        let style = model.chordStyle
        // The found number's own chords, drawn bright on top.
        let highlighted: [Path] = model.highlight.map { range in
            (range.lowerBound..<(range.upperBound - 1)).map(model.chord)
        } ?? []

        GeometryReader { geometry in
            let size = geometry.size
            let scale = Self.radius(in: size) * zoom
            ZStack {
                Canvas { context, size in
                    var unit = context
                    unit.translateBy(x: size.width / 2, y: size.height / 2)
                    // Zoom by drawing larger, not by scaling a rendered image, so lines stay sharp.
                    unit.scaleBy(x: scale, y: scale)

                    unit.drawBaked(baked)
                    var chords = unit
                    chords.blendMode = .plusLighter
                    for digit in 0..<10 {
                        let color = GraphicsContext.Shading.color(ChordLayout.color(digit).opacity(style.opacity))
                        chords.stroke(pending[digit], with: color, lineWidth: style.width / scale)
                        chords.stroke(paths[digit], with: color, lineWidth: style.width / scale)
                    }
                    if let live {
                        chords.stroke(live.path.trimmedPath(from: 0, to: live.progress),
                                      with: .color(.white), lineWidth: 2 / scale)
                    }
                    for chord in highlighted {
                        var glow = unit
                        glow.addFilter(.blur(radius: 4))
                        glow.stroke(chord, with: .color(.white.opacity(0.8)), lineWidth: 6 / scale)
                        unit.stroke(chord, with: .color(.white), lineWidth: 2.5 / scale)
                    }

                    for digit in 0..<10 {
                        unit.stroke(ChordLayout.arc(digit: digit, radius: 1.05),
                                    with: .color(ChordLayout.color(digit)),
                                    style: StrokeStyle(lineWidth: 6 / scale, lineCap: .round))
                    }
                }
                // Rasterise on the GPU; Core Graphics on the main thread can't keep up with dense runs.
                .drawingGroup()

                // Labels live outside the canvas, so their text is laid out once rather than every frame.
                ForEach(0..<10, id: \.self) { digit in
                    let p = ChordLayout.point(angle: ChordLayout.angle(digit: digit, fraction: 0.5), radius: 1.17)
                    Text("\(digit)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(ChordLayout.color(digit))
                        .position(x: size.width / 2 + p.x * scale, y: size.height / 2 + p.y * scale)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private static func radius(in size: CGSize) -> CGFloat {
        min(size.width, size.height) * 0.40
    }
}

/// The most recent digits of π, with the digit the diagram just reached highlighted.
/// One plain Text: per-digit views with animations cost a CPU-drawn layer every frame.
struct DigitStrip: View {
    let model: PiChordModel
    private let visible = 14

    var body: some View {
        let end = model.completed
        let start = max(0, end - visible + 1)
        var text = AttributedString(start > 0 ? "…" : "")
        for i in start...end {
            let digit = Int(model.digits[i])
            var piece = AttributedString("\(digit)\(i == 0 ? "." : "")")
            if model.highlight?.contains(i) == true {
                // The found number, in pink.
                piece.foregroundColor = Color(red: 0.96, green: 0.45, blue: 0.71)
                piece.font = .system(size: 24, weight: .bold, design: .monospaced)
            } else if i == end {
                piece.foregroundColor = ChordLayout.color(digit)
                piece.font = .system(size: 26, weight: .bold, design: .monospaced)
            } else {
                piece.foregroundColor = .gray
            }
            text += piece
        }
        return Text(text)
            .font(.system(.title3, design: .monospaced))
            .kerning(3)
            .frame(height: 32)
    }
}
