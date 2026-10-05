import Foundation

/// π's digits, bundled in pi-digits.bin: "3" then 10,000,000 decimals, two digits per byte (high
/// nibble first). An odd count ends with a 0xF filler nibble.
enum PiDigits {
    /// 3 followed by the first 1,000,000 decimals: everything the visualizations use.
    static let all: [UInt8] = unpack(limit: 1_000_001)

    /// 3 followed by every bundled decimal, as one byte per digit (0...9), for searching.
    static let extended: Data = Data(unpack(limit: .max))

    /// How many decimals the search covers.
    static var searchableDecimals: Int { extended.count - 1 }

    /// 1-based position after the decimal point where `pattern` (digits 0...9) first appears, or nil.
    static func position(of pattern: [UInt8]) -> Int? {
        guard !pattern.isEmpty, let range = extended.range(of: Data(pattern), in: 1..<extended.count) else { return nil }
        return range.lowerBound
    }

    /// Decimals in a 1-based range, as text.
    static func decimals(from first: Int, count: Int) -> String {
        let start = max(first, 1), end = min(first + count, extended.count)
        guard start < end else { return "" }
        return String(extended[start..<end].map { Character(String($0)) })
    }

    private static let packed = load("pi-digits")

    /// A bundled .bin of packed digits.
    static func load(_ name: String) -> Data {
        guard let url = Bundle.main.url(forResource: name, withExtension: "bin"),
              let data = try? Data(contentsOf: url) else {
            fatalError("\(name).bin is missing from the app bundle")
        }
        return data
    }

    private static func unpack(limit: Int) -> [UInt8] {
        unpack(packed, limit: limit)
    }

    /// Two digits per byte, high nibble first; a trailing 0xF nibble is padding.
    static func unpack(_ packed: Data, limit: Int) -> [UInt8] {
        var total = packed.count * 2
        if packed.last.map({ $0 & 0x0F == 0x0F }) == true { total -= 1 }
        let count = min(total, limit)
        var digits = [UInt8](repeating: 0, count: count)
        packed.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            digits.withUnsafeMutableBufferPointer { out in
                for i in 0..<count {
                    let byte = bytes[i >> 1]
                    out[i] = i & 1 == 0 ? byte >> 4 : byte & 0x0F
                }
            }
        }
        return digits
    }
}

/// The numbers whose digits the Chords and 3D Walk can draw, to compare π with others.
enum Constant: String, CaseIterable, Identifiable {
    case pi = "π"
    case e = "e"
    case sqrt2 = "√2"
    case phi = "φ"

    var id: Self { self }

    /// The integer digit followed by 1,000,000 decimals.
    var digits: [UInt8] {
        switch self {
        case .pi: PiDigits.all
        case .e: Self.eDigits
        case .sqrt2: Self.sqrt2Digits
        case .phi: Self.phiDigits
        }
    }

    private static let eDigits = PiDigits.unpack(PiDigits.load("e-digits"), limit: 1_000_001)
    private static let sqrt2Digits = PiDigits.unpack(PiDigits.load("sqrt2-digits"), limit: 1_000_001)
    private static let phiDigits = PiDigits.unpack(PiDigits.load("phi-digits"), limit: 1_000_001)
}
