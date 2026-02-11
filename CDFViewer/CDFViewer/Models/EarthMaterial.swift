import SceneKit
import AppKit

/// Manages the Earth's appearance with seasonal textures, day/night cycle, and city lights
class EarthMaterial {
    // Monthly Blue Marble textures (0-indexed internally, nil = not yet loaded)
    private var monthlyTextures: [NSImage?] = Array(repeating: nil, count: 12)
    private var nightTexture: NSImage?

    // Current state
    private(set) var currentMonth: Int = 1  // 1-12

    // Cache for blended texture to avoid re-blending
    private var cachedBlendedTexture: NSImage?
    private var cachedBlendKey: String = ""

    // Track if background loading is complete
    private var isFullyLoaded = false

    init() {
        // Don't load anything in init - textures loaded lazily on first use
    }

    /// Loads a specific month's texture (lazy loading)
    private func loadTexture(for month: Int) -> NSImage {
        let idx = month - 1
        if let cached = monthlyTextures[idx] {
            return cached
        }

        let filename = String(format: "blue_marble_%02d", month)
        if let url = Bundle.main.url(forResource: filename, withExtension: "jpg"),
           let image = NSImage(contentsOf: url) {
            monthlyTextures[idx] = image
            return image
        } else {
            let fallback = createFallbackTexture()
            monthlyTextures[idx] = fallback
            return fallback
        }
    }

    /// Loads all remaining textures in background for smooth blending later
    func preloadRemainingTextures() {
        guard !isFullyLoaded else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            for month in 1...12 {
                _ = self.loadTexture(for: month)
            }
            self.isFullyLoaded = true
        }
    }

    /// Ensures night texture is loaded
    private func ensureNightTextureLoaded() {
        guard nightTexture == nil else { return }

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

        // Calculate blend factor: day 1 = 0% next, last day = ~97% next
        let blendFactor = CGFloat(day - 1) / CGFloat(daysInMonth)

        // Create cache key based on month and quantized blend factor (5% steps)
        let quantizedBlend = Int(blendFactor * 20) // 0-20 steps
        let cacheKey = "\(month)-\(quantizedBlend)"

        // Return cached texture if available
        if cacheKey == cachedBlendKey, let cached = cachedBlendedTexture {
            return cached
        }

        let nextMonth = (month % 12) + 1

        // Load current month's texture (lazy)
        let currentTexture = loadTexture(for: month)

        // Skip blending if near month boundaries (for performance)
        // Also skip if next month's texture isn't loaded yet
        if blendFactor < 0.05 || monthlyTextures[nextMonth - 1] == nil {
            cachedBlendedTexture = currentTexture
            cachedBlendKey = cacheKey
            return currentTexture
        } else if blendFactor > 0.95 {
            let nextTexture = loadTexture(for: nextMonth)
            cachedBlendedTexture = nextTexture
            cachedBlendKey = cacheKey
            return nextTexture
        }

        // Load next month's texture and blend
        let nextTexture = loadTexture(for: nextMonth)
        let blended = blendImages(currentTexture, nextTexture, factor: blendFactor)
        cachedBlendedTexture = blended
        cachedBlendKey = cacheKey
        return blended
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

    // MARK: - Star Sphere Rotation

    /// Calculates Greenwich Mean Sidereal Time (GMST) for star sphere rotation
    /// Returns the rotation angle in radians around the Y-axis (Earth's rotation axis)
    static func starSphereRotation(for date: Date) -> CGFloat {
        // Calculate Julian Date
        let j2000 = Date(timeIntervalSince1970: 946728000.0)  // Jan 1, 2000 12:00 UTC
        let daysSinceJ2000 = date.timeIntervalSince(j2000) / 86400.0

        // Calculate Julian centuries since J2000.0
        let T = daysSinceJ2000 / 36525.0

        // GMST at 0h UT in degrees (IAU 1982 formula)
        // GMST = 280.46061837 + 360.98564736629 * d + 0.000387933 * T^2 - T^3 / 38710000
        // where d = days since J2000.0 including fraction
        var gmstDegrees = 280.46061837
            + 360.98564736629 * daysSinceJ2000
            + 0.000387933 * T * T
            - T * T * T / 38710000.0

        // Normalize to 0-360
        gmstDegrees = gmstDegrees.truncatingRemainder(dividingBy: 360.0)
        if gmstDegrees < 0 { gmstDegrees += 360.0 }

        // Convert to radians
        // The star sphere needs to rotate opposite to Earth's rotation
        // (as Earth rotates east, stars appear to move west)
        let gmstRadians = gmstDegrees * .pi / 180.0

        return CGFloat(gmstRadians)
    }
}

// MARK: - Day/Night Shader

extension EarthMaterial {
    /// Creates a material with day/night blending for the Earth
    /// Uses SceneKit's built-in lighting + fragment shader to fade city lights
    func createMaterial(for date: Date) -> SCNMaterial {
        let material = SCNMaterial()

        // Set diffuse (day texture, blended for current month - loads lazily)
        let dayTexture = createBlendedDayTexture(for: date)
        material.diffuse.contents = dayTexture
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .clamp

        // Ensure night texture is loaded, then set emission
        ensureNightTextureLoaded()
        if let night = nightTexture {
            material.emission.contents = night
            material.emission.wrapS = .repeat
            material.emission.wrapT = .clamp
            material.emission.intensity = 2.5
        }

        // Start loading remaining textures in background for smooth blending later
        preloadRemainingTextures()

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
