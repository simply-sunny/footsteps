import SwiftUI
import Charts
import MapKit

/// Separate detailed summary sheet presenting day metrics, dwell mini-map, and Swift Charts.
public struct DayDetailView: View {
    public let history: DayHistory
    @Environment(\.dismiss) private var dismiss

    public init(history: DayHistory) {
        self.history = history
    }

    public enum BreakdownCategory: String, CaseIterable, Sendable {
        case stationary = "Stationary (Dwell)"
        case moving = "Moving"
        case unknown = "Unknown / Gaps"

        public var color: Color {
            switch self {
            case .stationary: return .orange
            case .moving: return .blue
            case .unknown: return Color(UIColor.systemGray4)
            }
        }
    }

    public struct BreakdownSlice: Identifiable, Sendable {
        public var id: String { category.rawValue }
        public let category: BreakdownCategory
        public let duration: TimeInterval
        public let color: Color

        public init(category: BreakdownCategory, duration: TimeInterval) {
            self.category = category
            self.duration = duration
            self.color = category.color
        }
    }

    public static func topPlaces(from places: [DayPlace], limit: Int = 5) -> [DayPlace] {
        let sorted = places.sorted { $0.totalDuration > $1.totalDuration }
        return Array(sorted.prefix(limit))
    }

    public static func breakdownSlices(for history: DayHistory) -> [BreakdownSlice] {
        [
            BreakdownSlice(category: .stationary, duration: history.stationaryDuration),
            BreakdownSlice(category: .moving, duration: history.movingDuration),
            BreakdownSlice(category: .unknown, duration: history.unknownDuration)
        ]
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // 1. Headline Row: Observed Distance, Place Count, Moving Duration
                    headlineSection

                    Divider()

                    // 2. WHERE MY TIME WENT: Dwell Mini-Map
                    whereMyTimeWentSection

                    Divider()

                    // 3. MY DAY: Cumulative Observed Distance Line
                    myDaySection

                    Divider()

                    // 4. TIME BY PLACE: Top-5 Bar Chart
                    timeByPlaceSection

                    Divider()

                    // 5. DAY BREAKDOWN: Stationary / Moving / Unknown Donut Chart
                    dayBreakdownSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle(history.selectedDate.formatted(date: .complete, time: .omitted))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.body.bold())
                }
            }
        }
    }

    // MARK: - 1. Headline Section

    private var headlineSection: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("DISTANCE")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                Text(DayHistory.formatDistance(history.observedDistanceMeters))
                    .font(.title2.bold())
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text("PLACES")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                Text("\(history.places.count)")
                    .font(.title2.bold())
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text("MOVING TIME")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                Text(DayHistory.formatDuration(history.movingDuration))
                    .font(.title2.bold())
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    // MARK: - 2. WHERE MY TIME WENT Section

    private var whereMyTimeWentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WHERE MY TIME WENT")
                .font(.footnote.bold())
                .foregroundColor(.secondary)

            if history.stays.isEmpty && history.singleObservations.isEmpty {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(UIColor.secondarySystemBackground))
                    .frame(height: 180)
                    .overlay(
                        Text("No stationary places recorded for this day.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    )
            } else {
                DwellMiniMapView(
                    stays: history.stays,
                    singleObservations: history.singleObservations
                )
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(UIColor.separator).opacity(0.5), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - 3. MY DAY Section

    private var myDaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MY DAY")
                    .font(.footnote.bold())
                    .foregroundColor(.secondary)
                Spacer()
                Text("Cumulative Distance")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if history.cumulativeDistanceSeries.isEmpty || history.observedDistanceMeters == 0 {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(UIColor.secondarySystemBackground))
                    .frame(height: 160)
                    .overlay(
                        Text("No continuous moving trajectory recorded.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    )
            } else {
                Chart {
                    ForEach(Array(history.cumulativeDistanceSeries.enumerated()), id: \.offset) { seriesIdx, series in
                        ForEach(series) { pt in
                            LineMark(
                                x: .value("Time", pt.timestamp),
                                y: .value("Distance", pt.distanceMeters / 1000.0),
                                series: .value("Series", seriesIdx)
                            )
                            .foregroundStyle(Color.blue)
                            .interpolationMethod(.linear)
                        }
                    }
                }
                .chartXScale(domain: history.dayInterval.start...history.dayInterval.end)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let val = value.as(Double.self) {
                                Text(String(format: "%.1f km", val))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 180)
            }
        }
    }

    // MARK: - 4. TIME BY PLACE Section

    private var timeByPlaceSection: some View {
        let topPlaces = Self.topPlaces(from: history.places, limit: 5)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("TIME BY PLACE")
                    .font(.footnote.bold())
                    .foregroundColor(.secondary)
                Spacer()
                Text("Top 5 Places")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if topPlaces.isEmpty {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(UIColor.secondarySystemBackground))
                    .frame(height: 120)
                    .overlay(
                        Text("No dwell places identified.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    )
            } else {
                Chart(topPlaces) { place in
                    BarMark(
                        x: .value("Duration", place.totalDuration / 60.0),
                        y: .value("Place", place.label)
                    )
                    .foregroundStyle(Color.orange.gradient)
                    .cornerRadius(4)
                    .annotation(position: .trailing, alignment: .leading) {
                        Text(DayHistory.formatDuration(place.totalDuration))
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)
                            .padding(.leading, 4)
                    }
                }
                .chartXAxis {
                    AxisMarks(position: .bottom) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let min = value.as(Double.self) {
                                Text("\(Int(min))m")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: max(120, CGFloat(topPlaces.count * 38)))
            }
        }
    }

    // MARK: - 5. DAY BREAKDOWN Section

    private var dayBreakdownSection: some View {
        let slices = Self.breakdownSlices(for: history)
        let total = max(1.0, history.totalElapsedDuration)

        return VStack(alignment: .leading, spacing: 14) {
            Text("DAY BREAKDOWN")
                .font(.footnote.bold())
                .foregroundColor(.secondary)

            HStack(spacing: 20) {
                // Donut Sector Chart
                Chart(slices) { slice in
                    SectorMark(
                        angle: .value("Duration", slice.duration),
                        innerRadius: .ratio(0.62),
                        angularInset: 1.5
                    )
                    .foregroundStyle(slice.color)
                }
                .frame(width: 140, height: 140)

                // Legend
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(slices) { slice in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(slice.color)
                                .frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(slice.category.rawValue)
                                    .font(.caption.bold())
                                    .foregroundColor(.primary)
                                let pct = (slice.duration / total) * 100.0
                                Text("\(DayHistory.formatDuration(slice.duration)) · \(Int(pct))%")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 6)
        }
    }
}

/// Compact non-interactive mini-map for the "WHERE MY TIME WENT" section.
public struct DwellMiniMapView: UIViewRepresentable {
    public let stays: [DayStay]
    public let singleObservations: [TrajectoryPoint]

    public func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.isScrollEnabled = false
        mapView.isZoomEnabled = false
        mapView.isUserInteractionEnabled = false
        mapView.showsUserLocation = false
        mapView.showsCompass = false
        mapView.delegate = context.coordinator
        return mapView
    }

    public func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.removeOverlays(mapView.overlays)

        for stay in stays {
            let heat = DwellHeatOverlay.create(from: stay)
            mapView.addOverlay(heat)
        }

        for obs in singleObservations {
            let single = SingleObservationOverlay.create(from: obs)
            mapView.addOverlay(single)
        }

        if let firstRect = mapView.overlays.first?.boundingMapRect {
            let unionRect = mapView.overlays.reduce(firstRect) { $0.union($1.boundingMapRect) }
            if !unionRect.isNull && unionRect.size.width > 0 && unionRect.size.height > 0 {
                let padding = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
                mapView.setVisibleMapRect(unionRect, edgePadding: padding, animated: false)
            }
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public final class Coordinator: NSObject, MKMapViewDelegate {
        public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let heat = overlay as? DwellHeatOverlay {
                return DwellHeatRenderer(overlay: heat)
            }
            if let single = overlay as? SingleObservationOverlay {
                let r = MKCircleRenderer(circle: single)
                r.fillColor = UIColor.systemGray.withAlphaComponent(0.4)
                r.strokeColor = UIColor.systemGray
                r.lineWidth = 1.0
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
