import XCTest
import SwiftUI
@testable import CDFViewer

final class ColorVariantTests: XCTestCase {

    // Minimum squared distance in LCH space between any two generated colors
    // This ensures colors are visually distinguishable
    // LCH distance formula: sqrt(ΔL² + ΔC² + ΔH²) where H is scaled appropriately
    // A minimum distance of 400 (≈20 units in each dimension) ensures clear distinction
    let minimumLCHDistanceSquared: Double = 400.0

    // MARK: - LCH Distance Calculation

    /// Calculate squared Euclidean distance in LCH color space
    /// Note: Hue is circular, so we use the shorter arc distance
    func lchDistanceSquared(_ color1: Color, _ color2: Color) -> Double {
        let (l1, c1, h1) = color1.lchComponents
        let (l2, c2, h2) = color2.lchComponents

        let deltaL = l2 - l1
        let deltaC = c2 - c1

        // Hue is circular (0-360), use shorter arc
        var deltaH = h2 - h1
        if deltaH > 180 { deltaH -= 360 }
        if deltaH < -180 { deltaH += 360 }

        // Scale hue difference to be comparable with L and C
        // Hue ranges 0-360, L ranges 0-100, C ranges 0-130
        // Scale H by ~0.3 to make it comparable
        let scaledDeltaH = deltaH * 0.3

        return deltaL * deltaL + deltaC * deltaC + scaledDeltaH * scaledDeltaH
    }

    /// Calculate minimum pairwise distance among a set of colors
    func minimumPairwiseDistanceSquared(_ colors: [Color]) -> Double {
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

    // MARK: - Pure Color Tests

    func testPureWhiteVariants() {
        let white = Color.white
        let variants = VariableMetadata.generateColorVariants(from: white, count: 3)

        XCTAssertEqual(variants.count, 3, "Should generate 3 variants")

        let minDist = minimumPairwiseDistanceSquared(variants)
        print("Pure white variants - min distance²: \(minDist)")
        printColorDetails(variants, label: "White")

        XCTAssertGreaterThanOrEqual(minDist, minimumLCHDistanceSquared,
            "White variants should have sufficient distance. Got \(minDist), need \(minimumLCHDistanceSquared)")
    }

    func testPureBlackVariants() {
        let black = Color.black
        let variants = VariableMetadata.generateColorVariants(from: black, count: 3)

        XCTAssertEqual(variants.count, 3, "Should generate 3 variants")

        let minDist = minimumPairwiseDistanceSquared(variants)
        print("Pure black variants - min distance²: \(minDist)")
        printColorDetails(variants, label: "Black")

        XCTAssertGreaterThanOrEqual(minDist, minimumLCHDistanceSquared,
            "Black variants should have sufficient distance. Got \(minDist), need \(minimumLCHDistanceSquared)")
    }

    func testMidGrayVariants() {
        let gray = Color.gray
        let variants = VariableMetadata.generateColorVariants(from: gray, count: 3)

        XCTAssertEqual(variants.count, 3, "Should generate 3 variants")

        let minDist = minimumPairwiseDistanceSquared(variants)
        print("Mid gray variants - min distance²: \(minDist)")
        printColorDetails(variants, label: "Gray")

        XCTAssertGreaterThanOrEqual(minDist, minimumLCHDistanceSquared,
            "Gray variants should have sufficient distance. Got \(minDist), need \(minimumLCHDistanceSquared)")
    }

    // MARK: - Saturated Color Tests

    func testPureRedVariants() {
        let red = Color.red
        let variants = VariableMetadata.generateColorVariants(from: red, count: 3)

        let minDist = minimumPairwiseDistanceSquared(variants)
        print("Pure red variants - min distance²: \(minDist)")
        printColorDetails(variants, label: "Red")

        XCTAssertGreaterThanOrEqual(minDist, minimumLCHDistanceSquared,
            "Red variants should have sufficient distance. Got \(minDist), need \(minimumLCHDistanceSquared)")
    }

    func testPureBlueVariants() {
        let blue = Color.blue
        let variants = VariableMetadata.generateColorVariants(from: blue, count: 3)

        let minDist = minimumPairwiseDistanceSquared(variants)
        print("Pure blue variants - min distance²: \(minDist)")
        printColorDetails(variants, label: "Blue")

        XCTAssertGreaterThanOrEqual(minDist, minimumLCHDistanceSquared,
            "Blue variants should have sufficient distance. Got \(minDist), need \(minimumLCHDistanceSquared)")
    }

    func testPureGreenVariants() {
        let green = Color.green
        let variants = VariableMetadata.generateColorVariants(from: green, count: 3)

        let minDist = minimumPairwiseDistanceSquared(variants)
        print("Pure green variants - min distance²: \(minDist)")
        printColorDetails(variants, label: "Green")

        XCTAssertGreaterThanOrEqual(minDist, minimumLCHDistanceSquared,
            "Green variants should have sufficient distance. Got \(minDist), need \(minimumLCHDistanceSquared)")
    }

    // MARK: - Edge Case Tests

    func testVeryDarkBlueVariants() {
        // Dark blue - L < 30
        let darkBlue = Color(red: 0.0, green: 0.0, blue: 0.3)
        let variants = VariableMetadata.generateColorVariants(from: darkBlue, count: 3)

        let minDist = minimumPairwiseDistanceSquared(variants)
        print("Very dark blue variants - min distance²: \(minDist)")
        printColorDetails(variants, label: "Dark Blue")

        XCTAssertGreaterThanOrEqual(minDist, minimumLCHDistanceSquared,
            "Dark blue variants should have sufficient distance. Got \(minDist), need \(minimumLCHDistanceSquared)")
    }

    func testVeryLightYellowVariants() {
        // Light yellow - L > 70
        let lightYellow = Color(red: 1.0, green: 1.0, blue: 0.7)
        let variants = VariableMetadata.generateColorVariants(from: lightYellow, count: 3)

        let minDist = minimumPairwiseDistanceSquared(variants)
        print("Very light yellow variants - min distance²: \(minDist)")
        printColorDetails(variants, label: "Light Yellow")

        XCTAssertGreaterThanOrEqual(minDist, minimumLCHDistanceSquared,
            "Light yellow variants should have sufficient distance. Got \(minDist), need \(minimumLCHDistanceSquared)")
    }

    func testLowSaturationPinkVariants() {
        // Low saturation pink - C < 15
        let paleColor = Color(red: 0.6, green: 0.55, blue: 0.55)
        let variants = VariableMetadata.generateColorVariants(from: paleColor, count: 3)

        let minDist = minimumPairwiseDistanceSquared(variants)
        print("Low saturation variants - min distance²: \(minDist)")
        printColorDetails(variants, label: "Pale")

        XCTAssertGreaterThanOrEqual(minDist, minimumLCHDistanceSquared,
            "Low saturation variants should have sufficient distance. Got \(minDist), need \(minimumLCHDistanceSquared)")
    }

    // MARK: - Comprehensive Hue Coverage

    func testVariantsAcrossHueSpectrum() {
        // Test at multiple hue points to ensure algorithm works across the spectrum
        let hues: [(String, Color)] = [
            ("Red", Color(hue: 0.0, saturation: 0.8, brightness: 0.8)),
            ("Orange", Color(hue: 0.08, saturation: 0.8, brightness: 0.8)),
            ("Yellow", Color(hue: 0.17, saturation: 0.8, brightness: 0.8)),
            ("Green", Color(hue: 0.33, saturation: 0.8, brightness: 0.8)),
            ("Cyan", Color(hue: 0.5, saturation: 0.8, brightness: 0.8)),
            ("Blue", Color(hue: 0.67, saturation: 0.8, brightness: 0.8)),
            ("Purple", Color(hue: 0.75, saturation: 0.8, brightness: 0.8)),
            ("Magenta", Color(hue: 0.83, saturation: 0.8, brightness: 0.8)),
        ]

        for (name, color) in hues {
            let variants = VariableMetadata.generateColorVariants(from: color, count: 3)
            let minDist = minimumPairwiseDistanceSquared(variants)
            print("\(name) variants - min distance²: \(minDist)")

            XCTAssertGreaterThanOrEqual(minDist, minimumLCHDistanceSquared,
                "\(name) variants should have sufficient distance. Got \(minDist), need \(minimumLCHDistanceSquared)")
        }
    }

    func testVariantsAcrossLightnessRange() {
        // Test at different lightness levels with same hue
        let lightnessLevels: [(String, Double)] = [
            ("Very Dark (L=15)", 0.15),
            ("Dark (L=30)", 0.30),
            ("Medium-Dark (L=45)", 0.45),
            ("Medium (L=60)", 0.60),
            ("Light (L=75)", 0.75),
            ("Very Light (L=90)", 0.90),
        ]

        for (name, brightness) in lightnessLevels {
            let color = Color(hue: 0.6, saturation: 0.7, brightness: brightness)
            let variants = VariableMetadata.generateColorVariants(from: color, count: 3)
            let minDist = minimumPairwiseDistanceSquared(variants)
            print("\(name) variants - min distance²: \(minDist)")

            XCTAssertGreaterThanOrEqual(minDist, minimumLCHDistanceSquared,
                "\(name) variants should have sufficient distance. Got \(minDist), need \(minimumLCHDistanceSquared)")
        }
    }

    // MARK: - Five Color Variants

    func testFiveColorVariants() {
        let testColors: [Color] = [.white, .black, .gray, .red, .blue]

        for color in testColors {
            let variants = VariableMetadata.generateColorVariants(from: color, count: 5)

            XCTAssertEqual(variants.count, 5, "Should generate 5 variants")

            let minDist = minimumPairwiseDistanceSquared(variants)
            print("5-color variant test - min distance²: \(minDist)")

            XCTAssertGreaterThanOrEqual(minDist, minimumLCHDistanceSquared,
                "5-color variants should have sufficient distance. Got \(minDist), need \(minimumLCHDistanceSquared)")
        }
    }

    // MARK: - Helper

    func printColorDetails(_ colors: [Color], label: String) {
        print("\n\(label) color variants:")
        for (i, color) in colors.enumerated() {
            let (l, c, h) = color.lchComponents
            print("  [\(i)] L=\(String(format: "%.1f", l)), C=\(String(format: "%.1f", c)), H=\(String(format: "%.1f", h))°")
        }
        print("")
    }
}
