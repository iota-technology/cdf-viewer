import SwiftUI

/// High-performance line chart using Canvas for direct Core Graphics rendering
struct CanvasLineChart: View {
    let series: [CanvasChartSeries]
    let visibleXRange: ClosedRange<Date>?
    let fullXRange: ClosedRange<Date>?
    let cursorDate: Date?
    let isCursorPaused: Bool
    let isAnimating: Bool  // When true, hover is disabled (only click works)
    let colorForSeries: (String, Int) -> Color

    /// Optional Y-axis label (e.g., units like "meters" or "m/s")
    var yAxisLabel: String?

    // Callbacks for interaction
    var onZoom: ((CGFloat) -> Void)?
    var onPan: ((CGFloat) -> Void)?
    var onHover: ((Date?) -> Void)?
    var onTap: ((Date?) -> Void)?  // Date where click occurred (nil if outside plot area)

    // Layout constants
    private let leftPadding: CGFloat = 70   // Space for Y-axis labels
    private let rightPadding: CGFloat = 20
    private let topPadding: CGFloat = 20
    private let bottomPadding: CGFloat = 52 // Space for two-line X-axis labels (time + date)

    var body: some View {
        GeometryReader { geometry in
            let plotRect = CGRect(
                x: leftPadding,
                y: topPadding,
                width: geometry.size.width - leftPadding - rightPadding,
                height: geometry.size.height - topPadding - bottomPadding
            )

            ZStack {
                // Main canvas for chart rendering
                Canvas { context, size in
                    drawChart(context: context, size: size, plotRect: plotRect)
                }

                // Interaction overlay
                CanvasInteractionView(
                    plotRect: plotRect,
                    xRange: currentXRange,
                    isAnimating: isAnimating,
                    onZoom: onZoom,
                    onPan: onPan,
                    onHover: { date in onHover?(date) },
                    onHoverEnd: { onHover?(nil) },
                    onTap: onTap
                )
            }
        }
    }

    // MARK: - Computed Properties

    private var currentXRange: ClosedRange<Date> {
        visibleXRange ?? fullXRange ?? (Date.distantPast...Date.distantFuture)
    }

    /// Calculate Y range using binary search to find visible points (O(log n) + O(visible points))
    private func calculateYRange(xMin: Double, xMax: Double) -> ClosedRange<Double> {
        var minY = Double.infinity
        var maxY = -Double.infinity

        for s in series {
            // Use binary search to find the range of visible points
            let (startIdx, endIdx) = s.visibleRange(xMin: xMin, xMax: xMax)
            guard startIdx < endIdx else { continue }

            // Only iterate visible points
            for i in startIdx..<endIdx {
                let value = s.points[i].value
                if value.isFinite {
                    minY = min(minY, value)
                    maxY = max(maxY, value)
                }
            }
        }

        // Handle edge cases
        if minY == .infinity || maxY == -.infinity {
            return 0...1
        }
        if minY == maxY {
            return (minY - 1)...(maxY + 1)
        }

        // Add 5% padding
        let padding = (maxY - minY) * 0.05
        return (minY - padding)...(maxY + padding)
    }

    // MARK: - Drawing

    private func drawChart(context: GraphicsContext, size: CGSize, plotRect: CGRect) {
        let xRange = currentXRange
        let xMin = xRange.lowerBound.timeIntervalSince1970
        let xMax = xRange.upperBound.timeIntervalSince1970
        let yRange = calculateYRange(xMin: xMin, xMax: xMax)

        // Calculate X ticks once (used for both grid and labels)
        let (xTicks, xPrecision) = calculateAdaptiveXTicks(xRange: xRange, baseCount: 6)
        let xDivisions = xTicks.count - 1  // Number of divisions between ticks

        // Calculate Y divisions to make roughly square cells
        let yDivisions = calculateSquareYDivisions(plotRect: plotRect, xDivisions: xDivisions)

        // Draw grid and axes using unified tick positions
        drawGrid(context: context, plotRect: plotRect, xRange: xRange, xTicks: xTicks, yRange: yRange, yDivisions: yDivisions)
        drawYAxis(context: context, plotRect: plotRect, yRange: yRange, yDivisions: yDivisions)
        drawXAxis(context: context, plotRect: plotRect, xRange: xRange, xTicks: xTicks, precision: xPrecision)

        // Clip to plot area for line drawing
        var clippedContext = context
        clippedContext.clip(to: Path(plotRect))

        // Draw each series with downsampling for performance
        let targetPoints = Int(plotRect.width * 2)  // ~2 points per pixel for smooth lines
        for (index, s) in series.enumerated() {
            drawSeries(context: clippedContext, series: s, index: index, plotRect: plotRect,
                      xMin: xMin, xMax: xMax, yRange: yRange, targetPoints: targetPoints)
        }

        // Draw cursor line (unclipped for full height)
        if let cursor = cursorDate {
            drawCursor(context: context, date: cursor, plotRect: plotRect, xRange: xRange)
        }
    }

    /// Draws the chart grid lines.
    /// - Parameters:
    ///   - xRange: The visible data range (used for coordinate conversion to screen pixels)
    ///   - xTicks: Grid line positions aligned to "nice" intervals. These may extend slightly
    ///             beyond xRange because calculateXTicks aligns to round time values.
    private func drawGrid(context: GraphicsContext, plotRect: CGRect, xRange: ClosedRange<Date>, xTicks: [Date], yRange: ClosedRange<Double>, yDivisions: Int) {
        guard !xTicks.isEmpty else { return }

        let gridColor = Color.gray.opacity(0.3)

        // Horizontal grid lines
        let yStep = (yRange.upperBound - yRange.lowerBound) / Double(yDivisions)
        for i in 0...yDivisions {
            let y = yRange.lowerBound + Double(i) * yStep
            let yPos = yToPixel(y, in: plotRect, yRange: yRange)

            var path = Path()
            path.move(to: CGPoint(x: plotRect.minX, y: yPos))
            path.addLine(to: CGPoint(x: plotRect.maxX, y: yPos))
            context.stroke(path, with: .color(gridColor), lineWidth: 0.5)
        }

        // Vertical grid lines at X tick positions
        // Use xRange (not xTicks range) for coordinate conversion so grid lines
        // align exactly with tick marks and labels drawn by drawXAxis
        for tick in xTicks {
            let xPos = dateToPixel(tick, in: plotRect, xRange: xRange)
            var path = Path()
            path.move(to: CGPoint(x: xPos, y: plotRect.minY))
            path.addLine(to: CGPoint(x: xPos, y: plotRect.maxY))
            context.stroke(path, with: .color(gridColor), lineWidth: 0.5)
        }
    }

    /// Calculate number of Y divisions to make roughly square grid cells
    private func calculateSquareYDivisions(plotRect: CGRect, xDivisions: Int) -> Int {
        guard xDivisions > 0 else { return 5 }

        let cellWidth = plotRect.width / CGFloat(xDivisions)
        let idealYDivisions = plotRect.height / cellWidth

        // Round to nearest reasonable integer (min 3, max 10)
        let rounded = Int(round(idealYDivisions))
        return max(3, min(10, rounded))
    }

    private func drawYAxis(context: GraphicsContext, plotRect: CGRect, yRange: ClosedRange<Double>, yDivisions: Int) {
        let labelColor = Color.secondary
        let yStep = (yRange.upperBound - yRange.lowerBound) / Double(yDivisions)

        for i in 0...yDivisions {
            let y = yRange.lowerBound + Double(i) * yStep
            let yPos = yToPixel(y, in: plotRect, yRange: yRange)

            // Format value
            let text = formatYValue(y)
            let textObj = Text(text)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(labelColor)

            context.draw(
                textObj,
                at: CGPoint(x: plotRect.minX - 5, y: yPos),
                anchor: .trailing
            )
        }

        // Draw Y-axis label (units) if provided - rotated 90 degrees
        if let label = yAxisLabel {
            var rotatedContext = context
            let midY = plotRect.midY
            // Rotate around a point on the left side
            rotatedContext.translateBy(x: 12, y: midY)
            rotatedContext.rotate(by: .degrees(-90))

            let labelText = Text(label)
                .font(.system(size: 11))
                .foregroundColor(labelColor)

            rotatedContext.draw(labelText, at: .zero, anchor: .center)
        }
    }

    private func drawXAxis(context: GraphicsContext, plotRect: CGRect, xRange: ClosedRange<Date>, xTicks: [Date], precision: TimePrecision) {
        guard !xTicks.isEmpty else { return }

        let labelColor = Color.secondary
        let gridColor = Color.gray.opacity(0.3)  // Same as grid lines

        // Track which date was last shown to only show date at transitions
        var lastShownDateString: String? = nil
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let timeFormatter = DateFormatter()
        switch precision {
        case .hourMinute:
            timeFormatter.dateFormat = "HH:mm"
        case .seconds:
            timeFormatter.dateFormat = "HH:mm:ss"
        case .milliseconds:
            timeFormatter.dateFormat = "HH:mm:ss.SSS"
        }

        for tick in xTicks {
            let xPos = dateToPixel(tick, in: plotRect, xRange: xRange)
            let tickDateString = dateFormatter.string(from: tick)

            // Draw tick mark extending down from x-axis (same color as grid)
            var tickPath = Path()
            tickPath.move(to: CGPoint(x: xPos, y: plotRect.maxY))
            tickPath.addLine(to: CGPoint(x: xPos, y: plotRect.maxY + 4))
            context.stroke(tickPath, with: .color(gridColor), lineWidth: 1)

            // Draw time label (top line, below tick mark)
            let timeText = Text(timeFormatter.string(from: tick))
                .font(.system(size: 10))
                .foregroundColor(labelColor)

            context.draw(
                timeText,
                at: CGPoint(x: xPos, y: plotRect.maxY + 5),
                anchor: .top
            )

            // Draw date label only when date changes (or first tick)
            if lastShownDateString != tickDateString {
                let dateText = Text(tickDateString)
                    .font(.system(size: 9))
                    .foregroundColor(labelColor.opacity(0.8))

                context.draw(
                    dateText,
                    at: CGPoint(x: xPos, y: plotRect.maxY + 19),
                    anchor: .top
                )

                lastShownDateString = tickDateString
            }
        }
    }

    /// Time precision levels for X-axis labels
    private enum TimePrecision {
        case hourMinute    // HH:mm
        case seconds       // HH:mm:ss
        case milliseconds  // HH:mm:ss.SSS
    }

    /// Calculate X-axis ticks with adaptive count based on required precision
    /// Returns fewer ticks when milliseconds are needed to prevent label overlap
    private func calculateAdaptiveXTicks(xRange: ClosedRange<Date>, baseCount: Int) -> ([Date], TimePrecision) {
        // First pass: calculate with base count to determine precision needed
        let initialTicks = calculateXTicks(xRange: xRange, count: baseCount)

        // Check what precision we need
        let needsMillis = xTicksNeedMilliseconds(initialTicks)
        let needsSeconds = needsMillis || xTicksNeedSeconds(initialTicks)

        // Adjust tick count based on precision (wider labels need fewer ticks)
        let adjustedCount: Int
        let precision: TimePrecision
        if needsMillis {
            adjustedCount = max(3, baseCount - 2)  // Fewer ticks for millisecond labels
            precision = .milliseconds
        } else if needsSeconds {
            adjustedCount = baseCount
            precision = .seconds
        } else {
            adjustedCount = baseCount
            precision = .hourMinute
        }

        // Recalculate ticks if count changed
        let finalTicks = (adjustedCount != baseCount)
            ? calculateXTicks(xRange: xRange, count: adjustedCount)
            : initialTicks

        return (finalTicks, precision)
    }

    /// Determines if X-axis ticks need seconds precision
    /// Returns true if any consecutive ticks share the same hour:minute
    private func xTicksNeedSeconds(_ ticks: [Date]) -> Bool {
        guard ticks.count >= 2 else { return false }

        let calendar = Calendar.current
        for i in 1..<ticks.count {
            let prev = ticks[i - 1]
            let curr = ticks[i]

            let prevComponents = calendar.dateComponents([.hour, .minute], from: prev)
            let currComponents = calendar.dateComponents([.hour, .minute], from: curr)

            if prevComponents.hour == currComponents.hour &&
               prevComponents.minute == currComponents.minute {
                return true
            }
        }
        return false
    }

    /// Determines if X-axis ticks need milliseconds precision
    /// Returns true if any consecutive ticks share the same second
    private func xTicksNeedMilliseconds(_ ticks: [Date]) -> Bool {
        guard ticks.count >= 2 else { return false }

        let calendar = Calendar.current
        for i in 1..<ticks.count {
            let prev = ticks[i - 1]
            let curr = ticks[i]

            let prevComponents = calendar.dateComponents([.hour, .minute, .second], from: prev)
            let currComponents = calendar.dateComponents([.hour, .minute, .second], from: curr)

            if prevComponents.hour == currComponents.hour &&
               prevComponents.minute == currComponents.minute &&
               prevComponents.second == currComponents.second {
                return true
            }
        }
        return false
    }

    private func drawSeries(context: GraphicsContext, series: CanvasChartSeries, index: Int,
                           plotRect: CGRect, xMin: Double, xMax: Double,
                           yRange: ClosedRange<Double>, targetPoints: Int) {
        let color = colorForSeries(series.name, index)

        // Use binary search to find visible range (O(log n))
        let margin = (xMax - xMin) * 0.01
        let (startIdx, endIdx) = series.visibleRange(xMin: xMin - margin, xMax: xMax + margin)

        let visibleCount = endIdx - startIdx
        guard visibleCount >= 2 else { return }

        // Downsample if we have more points than needed
        let points: [(timestamp: Double, value: Double)]
        if visibleCount > targetPoints {
            points = downsampleMinMax(series: series, startIdx: startIdx, endIdx: endIdx,
                                     targetBuckets: targetPoints / 2)
        } else {
            // Use points directly without creating new array
            points = (startIdx..<endIdx).compactMap { i in
                let p = series.points[i]
                return p.value.isFinite ? (p.timestamp, p.value) : nil
            }
        }

        guard points.count >= 2 else { return }

        // Build path
        var path = Path()
        var lastTimestamp: Double?
        let avgSpacing = (xMax - xMin) / Double(points.count)

        for point in points {
            let x = timestampToPixel(point.timestamp, in: plotRect, xMin: xMin, xMax: xMax)
            let y = yToPixel(point.value, in: plotRect, yRange: yRange)
            let cgPoint = CGPoint(x: x, y: y)

            // Check for data gap
            let isGap: Bool
            if let last = lastTimestamp {
                isGap = (point.timestamp - last) > avgSpacing * 3
            } else {
                isGap = false
            }

            if path.isEmpty || isGap {
                path.move(to: cgPoint)
            } else {
                path.addLine(to: cgPoint)
            }
            lastTimestamp = point.timestamp
        }

        context.stroke(path, with: .color(color), lineWidth: 1)
    }

    /// Min-max downsampling: preserves peaks and valleys for visual accuracy
    /// Each bucket outputs its min and max values, maintaining the visual shape
    private func downsampleMinMax(series: CanvasChartSeries, startIdx: Int, endIdx: Int,
                                  targetBuckets: Int) -> [(timestamp: Double, value: Double)] {
        let count = endIdx - startIdx
        let bucketSize = max(1, count / targetBuckets)
        var result: [(timestamp: Double, value: Double)] = []
        result.reserveCapacity(targetBuckets * 2)

        var i = startIdx
        while i < endIdx {
            let bucketEnd = min(i + bucketSize, endIdx)

            var minVal = Double.infinity
            var maxVal = -Double.infinity
            var minIdx = i
            var maxIdx = i

            // Find min and max in this bucket
            for j in i..<bucketEnd {
                let p = series.points[j]
                guard p.value.isFinite else { continue }
                if p.value < minVal {
                    minVal = p.value
                    minIdx = j
                }
                if p.value > maxVal {
                    maxVal = p.value
                    maxIdx = j
                }
            }

            // Add min and max in timestamp order (preserves correct line direction)
            if minVal.isFinite && maxVal.isFinite {
                if minIdx <= maxIdx {
                    result.append((series.points[minIdx].timestamp, minVal))
                    if minIdx != maxIdx {
                        result.append((series.points[maxIdx].timestamp, maxVal))
                    }
                } else {
                    result.append((series.points[maxIdx].timestamp, maxVal))
                    result.append((series.points[minIdx].timestamp, minVal))
                }
            }

            i = bucketEnd
        }

        return result
    }

    private func drawCursor(context: GraphicsContext, date: Date, plotRect: CGRect, xRange: ClosedRange<Date>) {
        let xPos = dateToPixel(date, in: plotRect, xRange: xRange)

        guard xPos >= plotRect.minX && xPos <= plotRect.maxX else { return }

        var path = Path()
        path.move(to: CGPoint(x: xPos, y: plotRect.minY))
        path.addLine(to: CGPoint(x: xPos, y: plotRect.maxY))

        let color: Color = isCursorPaused ? .orange.opacity(0.7) : .gray.opacity(0.5)
        let lineWidth: CGFloat = isCursorPaused ? 2 : 1
        let dash: [CGFloat] = isCursorPaused ? [] : [5, 5]

        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, dash: dash))
    }

    // MARK: - Coordinate Conversion

    private func dateToPixel(_ date: Date, in rect: CGRect, xRange: ClosedRange<Date>) -> CGFloat {
        let xMin = xRange.lowerBound.timeIntervalSince1970
        let xMax = xRange.upperBound.timeIntervalSince1970
        let rangeDuration = xMax - xMin
        guard rangeDuration > 0 else { return rect.midX }  // Avoid division by zero
        let fraction = (date.timeIntervalSince1970 - xMin) / rangeDuration
        return rect.minX + CGFloat(fraction) * rect.width
    }

    private func timestampToPixel(_ timestamp: Double, in rect: CGRect, xMin: Double, xMax: Double) -> CGFloat {
        let rangeDuration = xMax - xMin
        guard rangeDuration > 0 else { return rect.midX }  // Avoid division by zero
        let fraction = (timestamp - xMin) / rangeDuration
        return rect.minX + CGFloat(fraction) * rect.width
    }

    private func yToPixel(_ value: Double, in rect: CGRect, yRange: ClosedRange<Double>) -> CGFloat {
        let rangeSpan = yRange.upperBound - yRange.lowerBound
        guard rangeSpan > 0 else { return rect.midY }  // Avoid division by zero
        let fraction = (value - yRange.lowerBound) / rangeSpan
        // Y is inverted (0 at top)
        return rect.maxY - CGFloat(fraction) * rect.height
    }

    // MARK: - Formatting

    private func formatYValue(_ value: Double) -> String {
        let absValue = abs(value)
        if absValue >= 1_000_000 {
            return String(format: "%.2e", value)
        } else if absValue >= 1000 {
            return String(format: "%.0f", value)
        } else if absValue >= 1 {
            return String(format: "%.2f", value)
        } else if absValue >= 0.01 {
            return String(format: "%.4f", value)
        } else {
            return String(format: "%.2e", value)
        }
    }

    /// Calculates X-axis tick positions aligned to "nice" time intervals.
    /// Returns at least one tick for any valid range. Ticks are aligned to round time values
    /// (e.g., on the minute, on 5-second boundaries) so panning feels like sliding paper.
    private func calculateXTicks(xRange: ClosedRange<Date>, count: Int) -> [Date] {
        let duration = xRange.upperBound.timeIntervalSince(xRange.lowerBound)
        guard duration > 0 else {
            // Degenerate case: zero-width range, return single tick at start
            return [xRange.lowerBound]
        }
        let idealStep = duration / Double(count)

        // Find a "nice" step size that divides evenly into time units
        let niceStep = niceTimeInterval(idealStep)

        // Find the first tick at or after the range start, aligned to the nice interval
        let startTimestamp = xRange.lowerBound.timeIntervalSince1970
        let endTimestamp = xRange.upperBound.timeIntervalSince1970

        // Align to the nice interval (floor to previous round value)
        let firstTickTimestamp = floor(startTimestamp / niceStep) * niceStep

        // Generate ticks
        var ticks: [Date] = []
        var timestamp = firstTickTimestamp
        while timestamp <= endTimestamp + niceStep * 0.01 {  // Small tolerance for floating point
            if timestamp >= startTimestamp - niceStep * 0.01 {
                ticks.append(Date(timeIntervalSince1970: timestamp))
            }
            timestamp += niceStep
        }

        return ticks
    }

    /// Find a "nice" time interval close to the target
    /// Returns intervals like 1s, 2s, 5s, 10s, 15s, 30s, 1min, 2min, 5min, etc.
    private func niceTimeInterval(_ target: TimeInterval) -> TimeInterval {
        // Define nice intervals in seconds
        let niceIntervals: [TimeInterval] = [
            0.001, 0.002, 0.005, 0.01, 0.02, 0.05,           // milliseconds
            0.1, 0.2, 0.5,                                    // tenths of seconds
            1, 2, 5, 10, 15, 30,                              // seconds
            60, 2*60, 5*60, 10*60, 15*60, 30*60,              // minutes
            3600, 2*3600, 6*3600, 12*3600,                    // hours
            86400, 2*86400, 7*86400                           // days
        ]

        // Find the closest nice interval
        var bestInterval = niceIntervals[0]
        var bestDiff = abs(target - bestInterval)

        for interval in niceIntervals {
            let diff = abs(target - interval)
            if diff < bestDiff {
                bestDiff = diff
                bestInterval = interval
            }
        }

        return bestInterval
    }
}

// MARK: - Data Models

struct CanvasChartSeries: Identifiable {
    let id = UUID()
    let name: String
    let points: [CanvasChartPoint]

    /// Binary search to find the range of points within [xMin, xMax]
    /// Returns (startIndex, endIndex) where endIndex is exclusive
    func visibleRange(xMin: Double, xMax: Double) -> (Int, Int) {
        guard !points.isEmpty else { return (0, 0) }

        // Find first point >= xMin using binary search
        var lo = 0
        var hi = points.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if points[mid].timestamp < xMin {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        let startIdx = lo

        // Find first point > xMax using binary search
        lo = startIdx
        hi = points.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if points[mid].timestamp <= xMax {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        let endIdx = lo

        return (startIdx, endIdx)
    }
}

struct CanvasChartPoint {
    let timestamp: Double  // TimeInterval since 1970 for fast comparison
    let value: Double
}

// MARK: - Interaction View

struct CanvasInteractionView: NSViewRepresentable {
    let plotRect: CGRect
    let xRange: ClosedRange<Date>
    let isAnimating: Bool  // When true, hover is disabled
    var onZoom: ((CGFloat) -> Void)?
    var onPan: ((CGFloat) -> Void)?
    var onHover: ((Date) -> Void)?
    var onHoverEnd: (() -> Void)?
    var onTap: ((Date?) -> Void)?  // Date where click occurred

    func makeNSView(context: Context) -> CanvasInteractionNSView {
        let view = CanvasInteractionNSView()
        updateCallbacks(view)
        return view
    }

    func updateNSView(_ nsView: CanvasInteractionNSView, context: Context) {
        nsView.plotRect = plotRect
        nsView.xRange = xRange
        nsView.isAnimating = isAnimating
        updateCallbacks(nsView)
    }

    private func updateCallbacks(_ view: CanvasInteractionNSView) {
        view.onZoom = onZoom
        view.onPan = onPan
        view.onHover = onHover
        view.onHoverEnd = onHoverEnd
        view.onTap = onTap
    }
}

class CanvasInteractionNSView: NSView {
    var plotRect: CGRect = .zero
    var xRange: ClosedRange<Date> = Date.distantPast...Date.distantFuture
    var isAnimating: Bool = false  // When true, hover is disabled
    var onZoom: ((CGFloat) -> Void)?
    var onPan: ((CGFloat) -> Void)?
    var onHover: ((Date) -> Void)?
    var onHoverEnd: (() -> Void)?
    var onTap: ((Date?) -> Void)?  // Date where click occurred

    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaX
        if abs(delta) > 0.5 {
            onPan?(delta * 2)
        }
    }

    override func magnify(with event: NSEvent) {
        let scale = 1.0 + event.magnification
        if abs(event.magnification) > 0.001 {
            onZoom?(scale)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        // Ignore hover when animation is playing (user must click to stop animation)
        guard !isAnimating else { return }

        let location = convert(event.locationInWindow, from: nil)
        // Convert to flipped coordinates (NSView is not flipped by default)
        let flippedY = bounds.height - location.y

        // Check if within plot area
        if location.x >= plotRect.minX && location.x <= plotRect.maxX &&
           flippedY >= plotRect.minY && flippedY <= plotRect.maxY {
            // Convert X position to date
            let fraction = (location.x - plotRect.minX) / plotRect.width
            let xMin = xRange.lowerBound.timeIntervalSince1970
            let xMax = xRange.upperBound.timeIntervalSince1970
            let timestamp = xMin + Double(fraction) * (xMax - xMin)
            let date = Date(timeIntervalSince1970: timestamp)
            onHover?(date)
        }
    }

    override func mouseExited(with event: NSEvent) {
        onHoverEnd?()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 1 {
            let location = convert(event.locationInWindow, from: nil)
            let flippedY = bounds.height - location.y

            // Check if within plot area and compute date
            if location.x >= plotRect.minX && location.x <= plotRect.maxX &&
               flippedY >= plotRect.minY && flippedY <= plotRect.maxY {
                let fraction = (location.x - plotRect.minX) / plotRect.width
                let xMin = xRange.lowerBound.timeIntervalSince1970
                let xMax = xRange.upperBound.timeIntervalSince1970
                let timestamp = xMin + Double(fraction) * (xMax - xMin)
                let date = Date(timeIntervalSince1970: timestamp)
                onTap?(date)
            } else {
                onTap?(nil)
            }
        }
    }
}
