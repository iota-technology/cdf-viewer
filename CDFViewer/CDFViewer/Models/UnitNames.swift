import Foundation

/// Maps well-known unit abbreviations to human-readable English names
enum UnitNames {
    /// Known unit mappings (abbreviation → English name)
    private static let knownUnits: [String: String] = [
        "m": "Meters",
        "m/s": "Meters/second",
        "m/s^2": "Meters/second²",
        "km": "Kilometers",
        "km/s": "Kilometers/second",
        "rad": "Radians",
        "rad/s": "Radians/second",
        "deg": "Degrees",
        "deg/s": "Degrees/second",
        "A": "Amps",
        "V": "Volts",
        "W": "Watts",
        "Hz": "Hertz",
        "s": "Seconds",
        "ms": "Milliseconds",
        "us": "Microseconds",
        "ns": "Nanoseconds",
        "K": "Kelvin",
        "C": "Celsius",
        "Pa": "Pascals",
        "T": "Tesla",
        "nT": "Nanotesla",
    ]

    /// Format a unit for display on the Y-axis
    /// Returns "English Name (abbreviation)" or just the abbreviation if unknown
    static func displayName(for unit: String) -> String {
        // Handle empty/whitespace-only units
        let trimmed = unit.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return "Units"
        }

        // Look up the English name
        if let englishName = knownUnits[trimmed] {
            return "\(englishName) (\(trimmed))"
        }

        // Unknown unit - just return as-is
        return trimmed
    }
}
