import Foundation
import SwiftUI

/// User-configurable metadata for a single CDF variable
struct VariableMetadata: Codable, Equatable {
    /// Override for positional detection (nil = use heuristic)
    var isPositional: Bool?

    /// Custom color in hex format (nil = use palette)
    var customColor: String?

    /// Whether this metadata has any user overrides
    var hasOverrides: Bool {
        isPositional != nil || customColor != nil
    }
}

/// File-level metadata containing all variable overrides
struct FileMetadata: Codable {
    /// Version for future compatibility
    var version: Int = 1

    /// Variable overrides keyed by variable name
    var variableOverrides: [String: VariableMetadata] = [:]

    /// Check if there are any overrides
    var isEmpty: Bool {
        variableOverrides.isEmpty || variableOverrides.values.allSatisfy { !$0.hasOverrides }
    }
}

// MARK: - Color Utilities

extension Color {
    /// Create a Color from a hex string (e.g., "#FF6600" or "FF6600")
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        guard hexSanitized.count == 6,
              let intValue = UInt64(hexSanitized, radix: 16) else {
            return nil
        }

        let r = Double((intValue >> 16) & 0xFF) / 255.0
        let g = Double((intValue >> 8) & 0xFF) / 255.0
        let b = Double(intValue & 0xFF) / 255.0

        self.init(red: r, green: g, blue: b)
    }

    /// Convert Color to hex string
    var hexString: String? {
        guard let components = NSColor(self).usingColorSpace(.deviceRGB) else {
            return nil
        }

        let r = Int(components.redComponent * 255)
        let g = Int(components.greenComponent * 255)
        let b = Int(components.blueComponent * 255)

        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// Shift the hue by a given number of degrees
    func hueShifted(by degrees: Double) -> Color {
        guard let nsColor = NSColor(self).usingColorSpace(.deviceRGB) else {
            return self
        }

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        nsColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        // Shift hue (wrapping around 0-1 range)
        let shift = degrees / 360.0
        let newHue = (hue + CGFloat(shift)).truncatingRemainder(dividingBy: 1.0)
        let adjustedHue = newHue < 0 ? newHue + 1.0 : newHue

        return Color(hue: Double(adjustedHue), saturation: Double(saturation), brightness: Double(brightness), opacity: Double(alpha))
    }
}

// MARK: - Component Color Calculation

extension VariableMetadata {
    /// Get colors for vector components (X, Y, Z) based on base color
    /// X uses the base color, Y shifts by 30°, Z shifts by 60°
    static func componentColors(for baseColor: Color) -> (x: Color, y: Color, z: Color) {
        return (
            x: baseColor,
            y: baseColor.hueShifted(by: 30),
            z: baseColor.hueShifted(by: 60)
        )
    }
}
