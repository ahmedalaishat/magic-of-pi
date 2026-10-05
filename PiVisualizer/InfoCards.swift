import SwiftUI

/// The short "why?" explanation behind each mode.
enum ModeTopic {
    case chords, rods, walk, spring

    var title: String {
        switch self {
        case .chords: "Why it looks random"
        case .rods: "Why the rods never close"
        case .walk: "A random walk through π"
        case .spring: "Stacking the turns"
        }
    }

    var sections: [(icon: String, heading: String, text: String)] {
        switch self {
        case .chords:
            [("circle.dashed", "What you see",
              "The digits 0–9 sit around the ring. Every pair of neighbouring digits in π, like 3→1, 1→4, 4→1, draws one chord from the first digit to the second."),
             ("equal.circle", "Evenly spread",
              "In the first 100,000 digits each digit turns up between 9,902 and 10,137 times, and each of the 100 possible pairs between 934 and 1,100 times. No path is favoured, so the chords fill the circle evenly."),
             ("questionmark.circle", "Still a mystery",
              "Mathematicians believe π is \"normal\": every digit, pair and longer pattern appears equally often forever. It has been checked for trillions of digits, but nobody has proved it.")]
        case .rods:
            [("arrow.triangle.2.circlepath", "Two rods",
              "Rod 2 spins π times as fast as rod 1. For the drawing to close, both rods must be back at the start together: after n turns of rod 1, rod 2 must have made a whole number of turns, so π × n would be a whole number."),
             ("xmark.circle", "It never happens",
              "That would make π a fraction. Johann Lambert proved in 1761 that π is irrational: no fraction equals it. So the pen never lands exactly where it began, and the pattern keeps filling in forever."),
             ("scope", "Near misses",
              "It comes close when π × n is almost whole: 7π = 21.991, 106π = 333.009, 113π = 354.99997. Those are the fractions 22/7 and 355/113. Zu Chongzhi found 355/113 in the 5th century; it is right to 6 decimal places. Turn on Spotlight to zoom into the miss.")]
        case .walk:
            [("arrow.up.and.down.and.arrow.left.and.right", "Ten directions",
              "Each digit is one step in its own direction: the ten side corners of an icosahedron. Digits that differ by 5 point exactly opposite, so a 0 followed by a 5 steps back to where it was."),
             ("figure.walk.motion", "Random-looking steps",
              "If π's digits behave like random numbers, the path wanders like a particle drifting in water (Brownian motion): tangles, sudden runs, and no overall direction."),
             ("ruler", "How far it gets",
              "A random walk of N steps typically ends about √N steps from the start: around 100 for 10,000 steps, 316 for 100,000. π's walk ends 94 and 117 steps away: well within what randomness produces.")]
        case .spring:
            [("water.waves", "Time as height",
              "These are the 1 : π rods again, but every turn lifts the trail a little higher. From the side the loops stack into a spring; from the top you see the flat drawing."),
             ("circle.circle", "Loops that line up",
              "The white loops are turn 0 and the near misses at turns 7, 106 and 113. Because 7π, 106π and 113π are almost whole numbers, those loops land almost exactly on top of turn 0's. Try Top view."),
             ("infinity", "But never exactly",
              "Even turn 113's loop misses turn 0's by about a billionth of the drawing's size, and later turns get closer still without ever touching, because π is irrational.")]
        }
    }
}

struct InfoSheet: View {
    let topic: ModeTopic
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(topic.sections, id: \.heading) { section in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: section.icon)
                                .font(.title2)
                                .foregroundStyle(.purple)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(section.heading).font(.headline)
                                Text(section.text)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle(topic.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
