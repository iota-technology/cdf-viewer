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

    /// Extract LCH (Lightness, Chroma, Hue) values from this color
    var lchComponents: (l: Double, c: Double, h: Double) {
        guard let nsColor = NSColor(self).usingColorSpace(.deviceRGB) else {
            return (50, 0, 0)
        }

        // Get RGB components
        var r = Double(nsColor.redComponent)
        var g = Double(nsColor.greenComponent)
        var b = Double(nsColor.blueComponent)

        // sRGB to linear RGB (inverse gamma)
        func linearize(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        r = linearize(r)
        g = linearize(g)
        b = linearize(b)

        // Linear RGB to XYZ (D65)
        let x = 0.4124564 * r + 0.3575761 * g + 0.1804375 * b
        let y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
        let z = 0.0193339 * r + 0.1191920 * g + 0.9503041 * b

        // XYZ to LAB (D65 white point)
        let xn = 0.95047
        let yn = 1.0
        let zn = 1.08883

        func f(_ t: Double) -> Double {
            let delta = 6.0 / 29.0
            return t > delta * delta * delta ? pow(t, 1.0 / 3.0) : t / (3.0 * delta * delta) + 4.0 / 29.0
        }

        let fx = f(x / xn)
        let fy = f(y / yn)
        let fz = f(z / zn)

        let l = 116.0 * fy - 16.0
        let a = 500.0 * (fx - fy)
        let labB = 200.0 * (fy - fz)

        // LAB to LCH
        let c = sqrt(a * a + labB * labB)
        var h = atan2(labB, a) * 180.0 / .pi
        if h < 0 { h += 360.0 }

        return (l, c, h)
    }

    /// Create a color in LCH color space (perceptually uniform)
    /// - Parameters:
    ///   - lightness: L value (0-100)
    ///   - chroma: C value (0-~130 typical max)
    ///   - hue: H value in degrees (0-360)
    static func lch(lightness: Double, chroma: Double, hue: Double) -> Color {
        // LCH to LAB
        let hueRad = hue * .pi / 180.0
        let a = chroma * cos(hueRad)
        let b = chroma * sin(hueRad)

        // LAB to XYZ (D65 white point)
        let fy = (lightness + 16.0) / 116.0
        let fx = a / 500.0 + fy
        let fz = fy - b / 200.0

        let epsilon = 216.0 / 24389.0
        let kappa = 24389.0 / 27.0

        let xr = fx * fx * fx > epsilon ? fx * fx * fx : (116.0 * fx - 16.0) / kappa
        let yr = lightness > kappa * epsilon ? pow((lightness + 16.0) / 116.0, 3) : lightness / kappa
        let zr = fz * fz * fz > epsilon ? fz * fz * fz : (116.0 * fz - 16.0) / kappa

        // D65 white point
        let x = xr * 0.95047
        let y = yr * 1.0
        let z = zr * 1.08883

        // XYZ to linear sRGB
        var r = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z
        var g = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z
        var bl = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z

        // Apply sRGB gamma correction
        func gammaCorrect(_ c: Double) -> Double {
            c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1.0 / 2.4) - 0.055
        }

        r = gammaCorrect(r)
        g = gammaCorrect(g)
        bl = gammaCorrect(bl)

        // Clamp to valid range
        r = max(0, min(1, r))
        g = max(0, min(1, g))
        bl = max(0, min(1, bl))

        return Color(red: r, green: g, blue: bl, opacity: 1.0)
    }

    /// Create an LCH color variant preserving this color's L and C, but shifting H
    /// This keeps Y and Z "in theme" with X by matching lightness and chroma
    func lchHueShifted(by degrees: Double) -> Color {
        let (l, c, h) = self.lchComponents
        var newHue = h + degrees
        // Wrap hue to 0-360
        while newHue < 0 { newHue += 360 }
        while newHue >= 360 { newHue -= 360 }
        return Color.lch(lightness: l, chroma: c, hue: newHue)
    }

    /// Shift the hue by a given number of degrees (HSB-based, for backwards compatibility)
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
    /// Get colors for vector components (X, Y, Z) based on base color.
    /// Uses an adaptive LCH algorithm that handles edge cases:
    /// - Low chroma (near gray): adds chroma to create visible color differences
    /// - High chroma: shifts hue while preserving saturation
    /// - Dark colors: lightens subsequent components for visibility
    /// - Light colors: darkens subsequent components for visibility
    static func componentColors(for baseColor: Color) -> (x: Color, y: Color, z: Color) {
        let variants = generateColorVariants(from: baseColor, count: 3)
        return (
            x: variants[0],
            y: variants[1],
            z: variants[2]
        )
    }

    /// Get color for a specific vector component by name.
    /// Supports any vector size (2D, 3D, 4D quaternion, etc.)
    /// - Parameters:
    ///   - component: Component name (e.g., "x", "y", "z", "w", "[0]", "[1]", etc.)
    ///   - variable: The vector variable (used to get component names)
    ///   - baseColor: The base color to derive variants from
    /// - Returns: Color for the component, or baseColor if component not found
    static func colorForComponent(_ component: String, variable: CDFVariable, baseColor: Color) -> Color {
        guard let vectorSize = variable.vectorSize else {
            return baseColor
        }
        let componentNames = CDFColumn.componentNames(for: variable)
        guard let index = componentNames.firstIndex(of: component) else {
            return baseColor
        }
        let variants = generateColorVariants(from: baseColor, count: vectorSize)
        return variants[index]
    }

    /// Generate N visually distinct colors from a starting color using adaptive LCH adjustments.
    /// - Parameters:
    ///   - baseColor: The starting color (used as first variant)
    ///   - count: Number of colors to generate (2-5 recommended)
    /// - Returns: Array of colors starting with the base color
    static func generateColorVariants(from baseColor: Color, count: Int) -> [Color] {
        guard count > 0 else { return [] }
        guard count > 1 else { return [baseColor] }

        let (l, c, h) = baseColor.lchComponents
        var colors: [Color] = [baseColor]

        // Determine adjustments based on base color characteristics
        let isLowChroma = c < 15
        let isDark = l < 30
        let isLight = l > 70

        for i in 1..<count {
            let step = Double(i)

            // Calculate hue shift (alternating directions for better spread)
            let hueDirection = i.isMultiple(of: 2) ? 1.0 : -1.0
            let hueShift: Double
            if isLowChroma {
                hueShift = hueDirection * 30.0 * step
            } else {
                // Use 30° base shift for good separation
                hueShift = hueDirection * 30.0 * step
            }

            // Calculate chroma adjustment
            var newChroma = c
            if isLowChroma {
                // Add significant chroma to make colors distinguishable from gray
                newChroma = c + 25.0 * step
            } else if isDark || isLight {
                // For dark/light colors, also boost chroma to add color variety
                newChroma = c + 15.0 * step
            } else {
                // Slight chroma variation (±10%)
                let chromaVariation = i.isMultiple(of: 2) ? 0.9 : 1.1
                newChroma = c * chromaVariation
            }

            // Calculate lightness adjustment
            var newLightness = l
            if isDark {
                // Lighten subsequent colors significantly for visibility on dark backgrounds
                newLightness = l + 28.0 * step
            } else if isLight {
                // Darken subsequent colors significantly for visibility on light backgrounds
                newLightness = l - 28.0 * step
            }

            // Calculate new hue with wrapping
            var newHue = h + hueShift
            while newHue < 0 { newHue += 360 }
            while newHue >= 360 { newHue -= 360 }

            // Clamp values to valid ranges before creating color
            newLightness = max(10, min(90, newLightness))
            newChroma = max(0, min(130, newChroma))

            // Create color and add (Color.lch already clamps to sRGB gamut)
            colors.append(Color.lch(lightness: newLightness, chroma: newChroma, hue: newHue))
        }

        return colors
    }
}
