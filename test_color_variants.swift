#!/usr/bin/env swift

import AppKit
import Foundation

// MARK: - Color Extension (copied from VariableMetadata.swift)

extension NSColor {
    /// Extract LCH (Lightness, Chroma, Hue) values from this color
    var lchComponents: (l: Double, c: Double, h: Double) {
        guard let rgb = self.usingColorSpace(.deviceRGB) else {
            return (50, 0, 0)
        }

        // Get RGB components
        var r = Double(rgb.redComponent)
        var g = Double(rgb.greenComponent)
        var b = Double(rgb.blueComponent)

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

    /// Create a color in LCH color space
    static func lch(lightness: Double, chroma: Double, hue: Double) -> NSColor {
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

        return NSColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(bl), alpha: 1.0)
    }
}

// MARK: - Color Variant Generation (current algorithm)

func generateColorVariants(from baseColor: NSColor, count: Int) -> [NSColor] {
    guard count > 0 else { return [] }
    guard count > 1 else { return [baseColor] }

    let (l, c, h) = baseColor.lchComponents
    var colors: [NSColor] = [baseColor]

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

        // Create color and add
        colors.append(NSColor.lch(lightness: newLightness, chroma: newChroma, hue: newHue))
    }

    return colors
}

// MARK: - Test Functions

func lchDistanceSquared(_ color1: NSColor, _ color2: NSColor) -> Double {
    let (l1, c1, h1) = color1.lchComponents
    let (l2, c2, h2) = color2.lchComponents

    let deltaL = l2 - l1
    let deltaC = c2 - c1

    // Hue is circular (0-360), use shorter arc
    var deltaH = h2 - h1
    if deltaH > 180 { deltaH -= 360 }
    if deltaH < -180 { deltaH += 360 }

    // Scale hue difference to be comparable with L and C
    let scaledDeltaH = deltaH * 0.3

    return deltaL * deltaL + deltaC * deltaC + scaledDeltaH * scaledDeltaH
}

func minimumPairwiseDistanceSquared(_ colors: [NSColor]) -> Double {
    guard colors.count >= 2 else { return Double.infinity }

    var minDistance = Double.infinity
    for i in 0..<colors.count {
        for j in (i+1)..<colors.count {
            let dist = lchDistanceSquared(colors[i], colors[j])
            minDistance = min(minDistance, dist)
        }
    }
    return minDistance
}

func printColorDetails(_ colors: [NSColor], label: String) {
    print("\n\(label) color variants:")
    for (i, color) in colors.enumerated() {
        let (l, c, h) = color.lchComponents
        print("  [\(i)] L=\(String(format: "%5.1f", l)), C=\(String(format: "%5.1f", c)), H=\(String(format: "%5.1f", h))°")
    }
}

// MARK: - Run Tests

let minimumLCHDistanceSquared: Double = 400.0
var failures: [(String, Double)] = []

print("=" * 60)
print("Color Variant Algorithm Test")
print("Minimum required distance²: \(minimumLCHDistanceSquared)")
print("=" * 60)

// Test cases
let testCases: [(String, NSColor)] = [
    ("Pure White", NSColor.white),
    ("Pure Black", NSColor.black),
    ("Mid Gray", NSColor.gray),
    ("Pure Red", NSColor.red),
    ("Pure Blue", NSColor.blue),
    ("Pure Green", NSColor.green),
    ("Very Dark Blue", NSColor(red: 0.0, green: 0.0, blue: 0.3, alpha: 1.0)),
    ("Very Light Yellow", NSColor(red: 1.0, green: 1.0, blue: 0.7, alpha: 1.0)),
    ("Low Saturation", NSColor(red: 0.6, green: 0.55, blue: 0.55, alpha: 1.0)),
]

for (name, color) in testCases {
    let variants = generateColorVariants(from: color, count: 3)
    let minDist = minimumPairwiseDistanceSquared(variants)

    printColorDetails(variants, label: name)

    let status = minDist >= minimumLCHDistanceSquared ? "✓ PASS" : "✗ FAIL"
    print("  Min distance²: \(String(format: "%.1f", minDist)) \(status)")

    if minDist < minimumLCHDistanceSquared {
        failures.append((name, minDist))
    }
}

print("\n" + "=" * 60)
if failures.isEmpty {
    print("All tests PASSED!")
} else {
    print("FAILURES (\(failures.count)):")
    for (name, dist) in failures {
        print("  - \(name): distance² = \(String(format: "%.1f", dist)) (need \(minimumLCHDistanceSquared))")
    }
}
print("=" * 60)

// Helper for string multiplication
extension String {
    static func * (left: String, right: Int) -> String {
        return String(repeating: left, count: right)
    }
}
