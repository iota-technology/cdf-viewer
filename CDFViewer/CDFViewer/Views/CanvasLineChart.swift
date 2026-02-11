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

        // Draw grid and axes
        drawGrid(context: context, plotRect: plotRect, xRange: xRange, yRange: yRange)
        drawYAxis(context: context, plotRect: plotRect, yRange: yRange)
        drawXAxis(context: context, plotRect: plotRect, xRange: xRange)

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

    private func drawGrid(context: GraphicsContext, plotRect: CGRect, xRange: ClosedRange<Date>, yRange: ClosedRange<Double>) {
        let gridColor = Color.gray.opacity(0.2)

        // Horizontal grid lines (5 lines)
        let yStep = (yRange.upperBound - yRange.lowerBound) / 5
        for i in 0...5 {
            let y = yRange.lowerBound + Double(i) * yStep
            let yPos = yToPixel(y, in: plotRect, yRange: yRange)

            var path = Path()
            path.move(to: CGPoint(x: plotRect.minX, y: yPos))
            path.addLine(to: CGPoint(x: plotRect.maxX, y: yPos))
            context.stroke(path, with: .color(gridColor), lineWidth: 0.5)
        }

        // Vertical grid lines (based on time)
        let xTicks = calculateXTicks(xRange: xRange, count: 6)
        for tick in xTicks {
            let xPos = dateToPixel(tick, in: plotRect, xRange: xRange)
            var path = Path()
            path.move(to: CGPoint(x: xPos, y: plotRect.minY))
            path.addLine(to: CGPoint(x: xPos, y: plotRect.maxY))
            context.stroke(path, with: .color(gridColor), lineWidth: 0.5)
        }
    }

    private func drawYAxis(context: GraphicsContext, plotRect: CGRect, yRange: ClosedRange<Double>) {
        let labelColor = Color.secondary
        let yStep = (yRange.upperBound - yRange.lowerBound) / 5

        for i in 0...5 {
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

    private func drawXAxis(context: GraphicsContext, plotRect: CGRect, xRange: ClosedRange<Date>) {
        let labelColor = Color.secondary
        let xTicks = calculateXTicks(xRange: xRange, count: 6)

        // Determine if we need seconds precision (when consecutive ticks share the same hour:minute)
        let needsSeconds = xTicksNeedSeconds(xTicks)

        // Track which date was last shown to only show date at transitions
        var lastShownDateString: String? = nil
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = needsSeconds ? "HH:mm:ss" : "HH:mm"

        for tick in xTicks {
            let xPos = dateToPixel(tick, in: plotRect, xRange: xRange)
            let tickDateString = dateFormatter.string(from: tick)

            // Draw time label (top line, closer to chart)
            let timeText = Text(timeFormatter.string(from: tick))
                .font(.system(size: 10))
                .foregroundColor(labelColor)

            context.draw(
                timeText,
                at: CGPoint(x: xPos, y: plotRect.maxY + 6),
                anchor: .top
            )

            // Draw date label only when date changes (or first tick)
            if lastShownDateString != tickDateString {
                let dateText = Text(tickDateString)
                    .font(.system(size: 9))
                    .foregroundColor(labelColor.opacity(0.8))

                context.draw(
                    dateText,
                    at: CGPoint(x: xPos, y: plotRect.maxY + 20),
                    anchor: .top
                )

                lastShownDateString = tickDateString
            }
        }
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
        let fraction = (date.timeIntervalSince1970 - xMin) / (xMax - xMin)
        return rect.minX + CGFloat(fraction) * rect.width
    }

    private func timestampToPixel(_ timestamp: Double, in rect: CGRect, xMin: Double, xMax: Double) -> CGFloat {
        let fraction = (timestamp - xMin) / (xMax - xMin)
        return rect.minX + CGFloat(fraction) * rect.width
    }

    private func yToPixel(_ value: Double, in rect: CGRect, yRange: ClosedRange<Double>) -> CGFloat {
        let fraction = (value - yRange.lowerBound) / (yRange.upperBound - yRange.lowerBound)
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

    private func calculateXTicks(xRange: ClosedRange<Date>, count: Int) -> [Date] {
        let duration = xRange.upperBound.timeIntervalSince(xRange.lowerBound)
        let step = duration / Double(count)

        var ticks: [Date] = []
        for i in 0...count {
            let date = xRange.lowerBound.addingTimeInterval(Double(i) * step)
            ticks.append(date)
        }
        return ticks
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
