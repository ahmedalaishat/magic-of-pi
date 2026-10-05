import SwiftUI

/// Search π's digits for a number (a birthday, a PIN, anything) and show where it appears.
/// If the number reads as a date, other ways of writing the same date are searched too.
struct FindInPiView: View {
    /// Called with the digit count to walk to, when the match is within the 3D walk's reach.
    let onWalk: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var result: SearchResult?
    @State private var searching = false
    @State private var shownPosition = 0
    @FocusState private var focused: Bool

    struct Match: Identifiable, Equatable {
        let label: String
        let digits: String
        /// 1-based position of the first digit after the decimal point, or nil if absent.
        let position: Int?
        var id: String { label + digits }
    }

    struct SearchResult: Equatable {
        let query: String
        /// The number as typed first, then other ways to write the same date.
        let matches: [Match]
        /// As typed if found, otherwise the first other form that was.
        var best: Match? { matches.first { $0.position != nil } }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    TextField("e.g. your birthday, 300199", text: $query)
                        .keyboardType(.numberPad)
                        .font(.system(size: 30, weight: .semibold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .focused($focused)
                        .padding(.vertical, 14)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                        .onChange(of: query) { _, new in
                            let digits = String(new.filter(\.isNumber).prefix(10))
                            if digits != new { query = digits }
                        }

                    HStack {
                        Button("Find in π", action: search)
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                            .disabled(query.isEmpty || searching)
                        Button("Try 999999") {
                            query = "999999"
                            search()
                        }
                        .buttonStyle(.bordered)
                    }

                    if searching {
                        ProgressView("Searching \(PiDigits.searchableDecimals.formatted()) digits…")
                    } else if let result {
                        resultView(result)
                    } else {
                        Text("Type a date as DDMMYY or DDMMYYYY, a year, or any number. The search covers the first \(PiDigits.searchableDecimals.formatted()) digits of π.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Find in π")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { focused = true }
        }
    }

    @ViewBuilder
    private func resultView(_ result: SearchResult) -> some View {
        if let best = result.best, let position = best.position {
            VStack(spacing: 16) {
                if best.digits == result.query {
                    Text("found at digit").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text("\(result.query) isn't in the first \(PiDigits.searchableDecimals.formatted()) digits, but the same date, written \(best.digits) (\(best.label)), is at digit")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Text(shownPosition.formatted())
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .contentTransition(.numericText(value: Double(shownPosition)))
                    .foregroundStyle(LinearGradient(colors: [.cyan, .purple, .pink], startPoint: .leading, endPoint: .trailing))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                context(position: position, length: best.digits.count)
                Text(odds(for: best.digits.count))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if position + best.digits.count - 1 <= WalkModel.countOptions.max()! {
                    Button {
                        onWalk(position + best.digits.count)
                        dismiss()
                    } label: {
                        Label("Walk to it in 3D", systemImage: "figure.walk.motion")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                }
                otherForms(result, excluding: best)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
                Text("\(result.query) isn't in the first \(PiDigits.searchableDecimals.formatted()) digits")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(odds(for: result.query.count) + " It is in π somewhere further on.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// Where the other ways of writing the date appear.
    @ViewBuilder
    private func otherForms(_ result: SearchResult, excluding best: Match) -> some View {
        let others = result.matches.filter { $0 != best }
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Other ways to write it").font(.subheadline.weight(.semibold))
                ForEach(others) { match in
                    HStack {
                        Text(match.digits).font(.system(.body, design: .monospaced))
                        Text(match.label).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(match.position.map { "digit \($0.formatted())" } ?? "not found")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(match.position == nil ? .secondary : .primary)
                    }
                }
            }
            .padding(14)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    /// The match with a few digits either side.
    private func context(position: Int, length: Int) -> some View {
        let before = Text("…" + PiDigits.decimals(from: position - 8, count: min(8, position - 1))).foregroundStyle(.secondary)
        let match = Text(PiDigits.decimals(from: position, count: length)).foregroundStyle(.pink).bold()
        let after = Text(PiDigits.decimals(from: position + length, count: 8) + "…").foregroundStyle(.secondary)
        return Text("\(before)\(match)\(after)")
            .font(.system(.title3, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    /// How likely a number of this length is to appear somewhere in the searched digits.
    private func odds(for length: Int) -> String {
        let chance = 1 - exp(-Double(PiDigits.searchableDecimals) / pow(10, Double(length)))
        let percent = chance > 0.995 ? "almost always" : "about \(Int((chance * 100).rounded()))% of the time"
        return "Any \(length)-digit number turns up in the first \(PiDigits.searchableDecimals.formatted()) digits \(percent)."
    }

    private func search() {
        guard !query.isEmpty, !searching else { return }
        focused = false
        searching = true
        result = nil
        let typed = query
        Task {
            // Scanning ten million digits (and unpacking them the first time) stays off the main thread.
            let found = await Task.detached(priority: .userInitiated) { () -> SearchResult in
                let forms = [("as typed", typed)] + DateForms.alternatives(for: typed)
                let matches = forms.map { label, digits in
                    Match(label: label, digits: digits,
                          position: PiDigits.position(of: digits.compactMap { $0.wholeNumberValue.map(UInt8.init) }))
                }
                return SearchResult(query: typed, matches: matches)
            }.value
            searching = false
            result = found
            shownPosition = 0
            if let position = found.best?.position {
                // Roll the counter up to the position.
                withAnimation(.easeOut(duration: 1.2)) { shownPosition = position }
            }
        }
    }
}

/// Other ways of writing a date typed as DDMMYY or DDMMYYYY.
enum DateForms {
    static func alternatives(for typed: String) -> [(label: String, digits: String)] {
        let d = typed.compactMap(\.wholeNumberValue)
        let day: Int, month: Int, year: Int
        switch d.count {
        case 6:
            day = d[0] * 10 + d[1]; month = d[2] * 10 + d[3]
            let yy = d[4] * 10 + d[5]
            year = yy >= 30 ? 1900 + yy : 2000 + yy
        case 8:
            day = d[0] * 10 + d[1]; month = d[2] * 10 + d[3]
            year = d[4] * 1000 + d[5] * 100 + d[6] * 10 + d[7]
        default:
            return []
        }
        guard (1...31).contains(day), (1...12).contains(month) else { return [] }

        let dd = String(format: "%02d", day), mm = String(format: "%02d", month)
        let yy = String(format: "%02d", year % 100), yyyy = String(year)
        let forms = [
            ("day month year", dd + mm + yy),
            ("without leading zeros", "\(day)\(month)\(yy)"),
            ("day month", dd + mm),
            ("month day year (US)", mm + dd + yy),
            ("year month day", yy + mm + dd),
            ("full year", dd + mm + yyyy),
        ]
        // Drop duplicates and the form that was typed.
        var seen: Set<String> = [typed]
        return forms.filter { seen.insert($0.1).inserted }
    }
}
