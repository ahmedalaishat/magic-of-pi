import Foundation

/// Remembers choices between launches (UserDefaults), with a fallback for anything missing or invalid.
enum Stored {
    static func value<T>(_ key: String, default fallback: T) -> T {
        UserDefaults.standard.object(forKey: key) as? T ?? fallback
    }

    /// A stored value, only if it is one of `options`.
    static func choice<T: Equatable>(_ key: String, among options: [T], default fallback: T) -> T {
        let stored: T = value(key, default: fallback)
        return options.contains(stored) ? stored : fallback
    }

    static func set(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
