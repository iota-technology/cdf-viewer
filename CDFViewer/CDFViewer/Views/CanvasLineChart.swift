import SwiftUI

/// High-performance line chart using Canvas for direct Core Graphics rendering
struct CanvasLineChart: View {
    let series: [CanvasChartSeries]
    let visibleXRange: ClosedRange<Date>?
    let fullXRange: ClosedRange<Date>?
    let cursorDate: Date?
    let isCursorPaused: Bool
    let colorForSeries: (String, Int) -> Color

    /// Optional Y-axis label (e.g., units like "meters" or "m/s")
    var yAxisLabel: String?

    // Callbacks for interaction
    var onZoom: ((CGFloat) -> Void)?
    var onPan: ((CGFloat) -> Void)?
    var onHover: ((Date?) -> Void)?
    var onTap: (() -> Void)?

    // Layout constants
    private let leftPadding: CGFloat = 70   // Space for Y-axis labels
    private let rightPadding: CGFloat = 20
    private let topPadding: CGFloat = 20
    private let bottomPadding: CGFloat = 40 // Space for X-axis labels

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

    private var yRange: ClosedRange<Double> {
        let xRange = currentXRange
        var minY = Double.infinity
        var maxY = -Double.infinity

        for s in series {
            for point in s.points {
                // Only consider finite points in visible X range
                if point.value.isFinite &&
                   point.timestamp >= xRange.lowerBound.timeIntervalSince1970 &&
                   point.timestamp <= xRange.upperBound.timeIntervalSince1970 {
                    minY = min(minY, point.value)
                    maxY = max(maxY, point.value)
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
        let yRange = self.yRange

        // Draw grid and axes
        drawGrid(context: context, plotRect: plotRect, xRange: xRange, yRange: yRange)
        drawYAxis(context: context, plotRect: plotRect, yRange: yRange)
        drawXAxis(context: context, plotRect: plotRect, xRange: xRange)

        // Clip to plot area for line drawing
        var clippedContext = context
        clippedContext.clip(to: Path(plotRect))

        // Draw each series
        for (index, s) in series.enumerated() {
            drawSeries(context: clippedContext, series: s, index: index, plotRect: plotRect, xRange: xRange, yRange: yRange)
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

        for tick in xTicks {
            let xPos = dateToPixel(tick, in: plotRect, xRange: xRange)

            let text = Text(formatXDate(tick))
                .font(.system(size: 10))
                .foregroundColor(labelColor)

            context.draw(
                text,
                at: CGPoint(x: xPos, y: plotRect.maxY + 15),
                anchor: .top
            )
        }
    }

    private func drawSeries(context: GraphicsContext, series: CanvasChartSeries, index: Int, plotRect: CGRect, xRange: ClosedRange<Date>, yRange: ClosedRange<Double>) {
        let color = colorForSeries(series.name, index)
        let xMin = xRange.lowerBound.timeIntervalSince1970
        let xMax = xRange.upperBound.timeIntervalSince1970

        // Filter to visible points with small margin, excluding NaN/infinite values
        let margin = (xMax - xMin) * 0.01
        let visiblePoints = series.points.filter { point in
            point.timestamp >= (xMin - margin) && point.timestamp <= (xMax + margin) &&
            point.value.isFinite
        }

        guard visiblePoints.count >= 2 else { return }

        // Build path, handling gaps from filtered NaN values
        var path = Path()
        var lastTimestamp: Double?

        for point in visiblePoints {
            let x = timestampToPixel(point.timestamp, in: plotRect, xMin: xMin, xMax: xMax)
            let y = yToPixel(point.value, in: plotRect, yRange: yRange)
            let cgPoint = CGPoint(x: x, y: y)

            // Check for data gap (more than 2x average spacing suggests missing data)
            let isGap: Bool
            if let last = lastTimestamp, visiblePoints.count > 1 {
                let avgSpacing = (xMax - xMin) / Double(visiblePoints.count)
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

    private func formatXDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
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
}

struct CanvasChartPoint {
    let timestamp: Double  // TimeInterval since 1970 for fast comparison
    let value: Double
}

// MARK: - Interaction View

struct CanvasInteractionView: NSViewRepresentable {
    let plotRect: CGRect
    let xRange: ClosedRange<Date>
    var onZoom: ((CGFloat) -> Void)?
    var onPan: ((CGFloat) -> Void)?
    var onHover: ((Date) -> Void)?
    var onHoverEnd: (() -> Void)?
    var onTap: (() -> Void)?

    func makeNSView(context: Context) -> CanvasInteractionNSView {
        let view = CanvasInteractionNSView()
        updateCallbacks(view)
        return view
    }

    func updateNSView(_ nsView: CanvasInteractionNSView, context: Context) {
        nsView.plotRect = plotRect
        nsView.xRange = xRange
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
    var onZoom: ((CGFloat) -> Void)?
    var onPan: ((CGFloat) -> Void)?
    var onHover: ((Date) -> Void)?
    var onHoverEnd: (() -> Void)?
    var onTap: (() -> Void)?

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
            onTap?()
        }
    }
}
