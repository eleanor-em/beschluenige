import Charts
import SwiftUI

struct TimeseriesPoint: Identifiable, Sendable {
    let id: Int
    let date: Date
    let value: Double
}

struct TimeseriesView: View {
    let title: String
    let unit: String
    let color: Color
    let points: [TimeseriesPoint]

    @State private var visibleDomain: ClosedRange<Date>?
    @State private var baselineDomain: ClosedRange<Date>?
    @State private var gestureStartDomain: ClosedRange<Date>?

    private var fullDomain: ClosedRange<Date>? {
        guard let first = points.first, let last = points.last,
              first.date < last.date else { return nil }
        return first.date...last.date
    }

    private var activeDomain: ClosedRange<Date> {
        visibleDomain ?? fullDomain ?? Date()...Date()
    }

    var body: some View {
        if points.isEmpty {
            ContentUnavailableView(
                "No \(title) Data",
                systemImage: "chart.xyaxis.line"
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                statsBar
                chartView
                    .frame(height: 200)
            }
        }
    }

    private var statsBar: some View {
        let slice = visibleSlice
        return HStack(spacing: 16) {
            if let s = slice {
                statLabel("Min", value: s.min, unit: unit)
                statLabel("Avg", value: s.mean, unit: unit)
                statLabel("Max", value: s.max, unit: unit)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func statLabel(_ label: String, value: Double, unit: String) -> some View {
        HStack(spacing: 2) {
            Text("\(label):")
                .fontWeight(.medium)
            Text(String(format: "%.0f", value))
            Text(unit)
        }
    }

    private var chartView: some View {
        Chart(points) { point in
            LineMark(
                x: .value("Time", point.date),
                y: .value(title, point.value)
            )
            .foregroundStyle(color)
            .interpolationMethod(.linear)
        }
        .chartXScale(domain: activeDomain)
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour().minute().second())
            }
        }
        .gesture(panGesture)
        .gesture(zoomGesture)
        .onTapGesture(count: 2) {
            withAnimation(.easeInOut(duration: 0.3)) {
                visibleDomain = nil
                baselineDomain = nil
            }
        }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { gesture in
                guard let full = fullDomain else { return }
                if gestureStartDomain == nil {
                    gestureStartDomain = activeDomain
                }
                guard let start = gestureStartDomain else { return }

                let fullSpan = full.upperBound.timeIntervalSince(full.lowerBound)
                let fraction = gesture.translation.width / 300.0
                let shift = -fraction * fullSpan

                let domainSpan = start.upperBound.timeIntervalSince(start.lowerBound)
                var newLower = start.lowerBound.addingTimeInterval(shift)
                var newUpper = start.upperBound.addingTimeInterval(shift)

                // Clamp to full domain
                if newLower < full.lowerBound {
                    newLower = full.lowerBound
                    newUpper = newLower.addingTimeInterval(domainSpan)
                }
                if newUpper > full.upperBound {
                    newUpper = full.upperBound
                    newLower = newUpper.addingTimeInterval(-domainSpan)
                }

                if newLower < newUpper {
                    visibleDomain = newLower...newUpper
                    baselineDomain = visibleDomain
                }
            }
            .onEnded { _ in
                gestureStartDomain = nil
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { gesture in
                guard let full = fullDomain else { return }
                if baselineDomain == nil {
                    baselineDomain = activeDomain
                }
                guard let base = baselineDomain else { return }

                let scale = 1.0 / gesture.magnification
                let baseSpan = base.upperBound.timeIntervalSince(base.lowerBound)
                let newSpan = max(baseSpan * scale, 1.0)

                let center = base.lowerBound.addingTimeInterval(baseSpan / 2)
                var newLower = center.addingTimeInterval(-newSpan / 2)
                var newUpper = center.addingTimeInterval(newSpan / 2)

                // Clamp to full domain
                if newLower < full.lowerBound { newLower = full.lowerBound }
                if newUpper > full.upperBound { newUpper = full.upperBound }

                if newLower < newUpper {
                    visibleDomain = newLower...newUpper
                }
            }
            .onEnded { _ in
                baselineDomain = visibleDomain
            }
    }

    // MARK: - Stats

    private struct SliceStats {
        let min: Double
        let max: Double
        let mean: Double
    }

    private var visibleSlice: SliceStats? {
        let domain = activeDomain
        let filtered = points.filter { domain.contains($0.date) }
        guard !filtered.isEmpty else { return nil }

        var lo = Double.greatestFiniteMagnitude
        var hi = -Double.greatestFiniteMagnitude
        var sum = 0.0
        for p in filtered {
            lo = Swift.min(lo, p.value)
            hi = Swift.max(hi, p.value)
            sum += p.value
        }
        return SliceStats(
            min: lo,
            max: hi,
            mean: sum / Double(filtered.count)
        )
    }
}
