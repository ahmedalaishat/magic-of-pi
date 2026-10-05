import Foundation
import Testing
@testable import PiVisualizer

/// The maths behind the visualizations.
struct DigitsTests {
    @Test func piStartsCorrectly() {
        #expect(Array(PiDigits.all.prefix(20)) == [3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5, 8, 9, 7, 9, 3, 2, 3, 8, 4])
        #expect(PiDigits.all.count == 1_000_001)
        #expect(PiDigits.searchableDecimals == 10_000_000)
    }

    @Test func feynmanPoint() {
        // Six 9s in a row, starting at decimal 762.
        #expect(PiDigits.position(of: [9, 9, 9, 9, 9, 9]) == 762)
    }

    @Test func searchFindsFirstOccurrence() {
        #expect(PiDigits.position(of: [1, 4, 1, 5]) == 1)
        #expect(PiDigits.position(of: [3, 0, 0, 1, 9, 9]) == 1_721_511)
        #expect(PiDigits.decimals(from: 1, count: 5) == "14159")
    }

    @Test(arguments: [(Constant.e, "2718281828459045"), (.sqrt2, "1414213562373095"), (.phi, "1618033988749894")])
    func otherConstantsStartCorrectly(constant: Constant, prefix: String) {
        let digits = constant.digits
        #expect(digits.count == 1_000_001)
        #expect(digits.prefix(prefix.count).map(String.init).joined() == prefix)
    }
}

struct DateFormTests {
    @Test func birthdayAlternatives() {
        let forms = Set(DateForms.alternatives(for: "300199").map(\.digits))
        #expect(forms == ["30199", "3001", "013099", "990130", "30011999"])
    }

    @Test func notADate() {
        #expect(DateForms.alternatives(for: "999999").isEmpty)
        #expect(DateForms.alternatives(for: "1234").isEmpty)
    }
}

@MainActor
struct RodsTests {
    @Test func nearMissesAreTheBestFractionsOfPi() {
        let rods = RodsModel()
        rods.setStyle(.classic)
        // 22/7, 333/106 and 355/113.
        #expect(Array(rods.nearMisses.prefix(3)) == [7, 106, 113])
    }

    @Test func fourierOutlineRebuildsThePiGlyph() {
        // Summing every term at θ = 0 must land on the outline's first point.
        let x = PiOutline.terms.reduce(0) { $0 + $1.length * cos($1.phase) }
        let y = PiOutline.terms.reduce(0) { $0 + $1.length * sin($1.phase) }
        #expect(abs(x - Double(PiOutline.points[0].x)) < 1e-6)
        #expect(abs(y - Double(PiOutline.points[0].y)) < 1e-6)
    }
}
