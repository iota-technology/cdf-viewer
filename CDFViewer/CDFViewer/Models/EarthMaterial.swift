import SceneKit
import AppKit

/// Manages the Earth's appearance with seasonal textures, day/night cycle, and city lights
class EarthMaterial {
    // Monthly Blue Marble textures (0-indexed internally)
    private var monthlyTextures: [NSImage] = []
    private var nightTexture: NSImage?

    // Current state
    private(set) var currentMonth: Int = 1  // 1-12

    init() {
        loadTextures()
    }

    private func loadTextures() {
        // Load monthly textures (01-12)
        for month in 1...12 {
            let filename = String(format: "blue_marble_%02d", month)
            if let url = Bundle.main.url(forResource: filename, withExtension: "jpg"),
               let image = NSImage(contentsOf: url) {
                monthlyTextures.append(image)
            } else {
                monthlyTextures.append(createFallbackTexture())
            }
        }

        // Load night texture
        if let url = Bundle.main.url(forResource: "black_marble", withExtension: "jpg"),
           let image = NSImage(contentsOf: url) {
            nightTexture = image
        }
    }

    private func createFallbackTexture() -> NSImage {
        let size = NSSize(width: 64, height: 64)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(red: 0.1, green: 0.3, blue: 0.6, alpha: 1.0).setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }

    /// Creates a blended texture for the current date
    /// Blends between months based on day of month
    func createBlendedDayTexture(for date: Date) -> NSImage {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        let daysInMonth = calendar.range(of: .day, in: .month, for: date)?.count ?? 30

        currentMonth = month

        let currentIdx = month - 1  // 0-indexed
        let nextIdx = month % 12    // Wrap December -> January

        guard monthlyTextures.count == 12 else {
            return monthlyTextures.first ?? createFallbackTexture()
        }

        // Calculate blend factor: day 1 = 0% next, last day = ~97% next
        let blendFactor = CGFloat(day - 1) / CGFloat(daysInMonth)

        // Skip blending if near month boundaries (for performance)
        if blendFactor < 0.05 {
            return monthlyTextures[currentIdx]
        } else if blendFactor > 0.95 {
            return monthlyTextures[nextIdx]
        }

        // Blend textures
        return blendImages(monthlyTextures[currentIdx], monthlyTextures[nextIdx], factor: blendFactor)
    }

    /// Returns the night texture (Black Marble)
    var night: NSImage? {
        return nightTexture
    }

    /// Blends two images together
    private func blendImages(_ image1: NSImage, _ image2: NSImage, factor: CGFloat) -> NSImage {
        let size = image1.size
        let result = NSImage(size: size)

        result.lockFocus()

        // Draw first image
        image1.draw(in: NSRect(origin: .zero, size: size),
                    from: .zero,
                    operation: .copy,
                    fraction: 1.0)

        // Draw second image on top with blend factor
        image2.draw(in: NSRect(origin: .zero, size: size),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: factor)

        result.unlockFocus()

        return result
    }

    // MARK: - Sun Position

    /// Calculates the sun direction vector based on the given date/time
    /// Returns a normalized SCNVector3 pointing toward the sun
    static func sunDirection(for date: Date) -> SCNVector3 {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!

        // Get day of year (1-365)
        let dayOfYear = utcCalendar.ordinality(of: .day, in: .year, for: date) ?? 1

        // Get hour of day in UTC (0-24)
        let hour = utcCalendar.component(.hour, from: date)
        let minute = utcCalendar.component(.minute, from: date)
        let second = utcCalendar.component(.second, from: date)
        let hourDecimal = Double(hour) + Double(minute) / 60.0 + Double(second) / 3600.0

        // Calculate sun declination (latitude where sun is directly overhead)
        // Varies between +23.45° (summer solstice) and -23.45° (winter solstice)
        let declination = 23.45 * sin(2.0 * .pi * Double(dayOfYear - 81) / 365.0)
        let declinationRad = declination * .pi / 180.0

        // Calculate sun hour angle (longitude where sun is directly overhead)
        // The sun is at longitude 0° at 12:00 UTC, moves 15° per hour westward
        let hourAngle = (hourDecimal - 12.0) * 15.0
        let longitudeRad = -hourAngle * .pi / 180.0

        // Convert to Cartesian (ECEF-like)
        let latRad = declinationRad
        let lonRad = longitudeRad

        let x = cos(latRad) * cos(lonRad)
        let y = cos(latRad) * sin(lonRad)
        let z = sin(latRad)

        // Convert to SceneKit coordinates (Y up):
        // ECEF X -> SceneKit X
        // ECEF Y -> SceneKit -Z
        // ECEF Z -> SceneKit Y
        return SCNVector3(CGFloat(x), CGFloat(z), CGFloat(-y))
    }

    /// Returns the position for the sun light (far away in sun direction)
    static func sunPosition(for date: Date, distance: CGFloat = 1000) -> SCNVector3 {
        let dir = sunDirection(for: date)
        return SCNVector3(dir.x * distance, dir.y * distance, dir.z * distance)
    }
}

// MARK: - Day/Night Shader

extension EarthMaterial {
    /// Creates a material with day/night blending for the Earth
    /// Uses SceneKit's built-in lighting + fragment shader to fade city lights
    func createMaterial(for date: Date) -> SCNMaterial {
        let material = SCNMaterial()

        // Set diffuse (day texture, blended for current month)
        let dayTexture = createBlendedDayTexture(for: date)
        material.diffuse.contents = dayTexture
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .clamp

        // Set emission (night texture - city lights)
        if let night = nightTexture {
            material.emission.contents = night
            material.emission.wrapS = .repeat
            material.emission.wrapT = .clamp
            material.emission.intensity = 2.5
        }

        // Fragment shader: fade city lights based on lighting contribution
        // This runs AFTER lighting, so _lightingContribution is available
        // Note: SceneKit already added _surface.emission to _output.color, so we adjust it
        material.shaderModifiers = [
            .fragment: """
                // Calculate how lit this fragment is from diffuse lighting
                float lightLevel = (_lightingContribution.diffuse.r + _lightingContribution.diffuse.g + _lightingContribution.diffuse.b) / 3.0;

                // Night factor: 1.0 at terminator and night, fading to 0 about 15° into day side
                // sin(15°) ≈ 0.26, so lights start appearing when lightLevel drops below ~0.26
                // Lights reach 100% at terminator (lightLevel ≈ 0)
                float nightFactor = 1.0 - smoothstep(0.0, 0.26, lightLevel);

                // SceneKit already added full emission to output
                // We want: emission * cityTint * nightFactor
                // So adjust by: emission * (cityTint * nightFactor - 1.0)
                float3 cityTint = float3(1.0, 0.85, 0.5);
                float3 desiredEmission = _surface.emission.rgb * cityTint * nightFactor;
                float3 currentEmission = _surface.emission.rgb;  // What SceneKit added
                _output.color.rgb += desiredEmission - currentEmission;
                """
        ]

        // Material properties
        material.lightingModel = .lambert
        material.locksAmbientWithDiffuse = true

        return material
    }

    /// Updates an existing material for a new date
    func updateMaterial(_ material: SCNMaterial, for date: Date) {
        material.diffuse.contents = createBlendedDayTexture(for: date)
    }
}
