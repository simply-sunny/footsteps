import SwiftUI
import SwiftData
import CoreLocation
import MapKit

/// Primary user-facing view with quiet full-bleed MapKit map, floating controls, and Path/Time modes.
public struct DailyTrackerView: View {
    @ObservedObject private var locationManager = LocationManager.shared
    @AppStorage(LocationManager.trackingEnabledKey) private var isTrackingEnabled: Bool = true
    @AppStorage("showDiagnosticsMapOverlay") private var showDebugOverlay: Bool = false
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedDate: Date = Date()
    @State private var currentDateReference: Date = Date()
    @State private var selectedItemID: String? = nil
    @State private var mapDisplayMode: MapDisplayMode = .path
    @State private var isDetailPresented: Bool = false
    @State private var isSettingsPresented: Bool = false
    @State private var isDatePickerPresented: Bool = false
    @State private var recenterTrigger: Int = 0

    private var canGoNext: Bool {
        TrajectoryMath.canNavigateNext(from: selectedDate, now: currentDateReference)
    }

    public init() {}

    public var body: some View {
        ZStack(alignment: .top) {
            // 1. Full-bleed Trajectory Map Container
            DailyTrajectoryContainerView(
                selectedDate: selectedDate,
                currentDateReference: currentDateReference,
                mapDisplayMode: $mapDisplayMode,
                recenterTrigger: recenterTrigger,
                showDebugOverlay: showDebugOverlay,
                selectedItemID: $selectedItemID,
                isDetailPresented: $isDetailPresented,
                isSettingsPresented: $isSettingsPresented
            )
            .id(TrajectoryMath.dayInterval(for: selectedDate).start)
            .animation(nil, value: selectedDate)
            .edgesIgnoringSafeArea(.all)

            // 2. Top Status & Error Banners
            VStack(spacing: 8) {
                if let error = locationManager.lastError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text(error)
                            .font(.footnote)
                            .lineLimit(2)
                        Spacer()
                        Button("Dismiss") {
                            locationManager.lastError = nil
                        }
                        .font(.footnote.bold())
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
                }

                if locationManager.authorizationStatus == .notDetermined {
                    HStack(spacing: 8) {
                        Image(systemName: "location.circle.fill")
                            .foregroundColor(.blue)
                        Text("Enable location tracking to record footsteps.")
                            .font(.footnote)
                        Spacer()
                        Button("Enable") {
                            locationManager.requestPermissions()
                        }
                        .font(.footnote.bold())
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
                } else if locationManager.isReducedAccuracy {
                    HStack(spacing: 8) {
                        Image(systemName: "scope")
                            .foregroundColor(.orange)
                        Text("Precise location is off. Full accuracy needed.")
                            .font(.footnote)
                        Spacer()
                        Button("Enable Full") {
                            locationManager.requestFullAccuracy()
                        }
                        .font(.footnote.bold())
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
                }
            }
            .padding(.top, 54)
            .zIndex(10)

            // 3. Bottom Floating Controls Bar
            VStack {
                Spacer()
                bottomControlsBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
            .zIndex(20)
        }
        .sheet(isPresented: $isDatePickerPresented) {
            NavigationStack {
                VStack(spacing: 20) {
                    DatePicker(
                        "Select Date",
                        selection: $selectedDate,
                        in: ...currentDateReference,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .padding()

                    Spacer()
                }
                .navigationTitle("Choose Day")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            isDatePickerPresented = false
                        }
                        .font(.body.bold())
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .onChange(of: isTrackingEnabled) { _, isEnabled in
            locationManager.setTrackingEnabled(isEnabled)
        }
        .onChange(of: selectedDate) { _, _ in
            selectedItemID = nil
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                locationManager.refreshAuthorizationStatus()
                refreshCurrentDate()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            locationManager.refreshAuthorizationStatus()
            refreshCurrentDate()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            refreshCurrentDate()
        }
    }

    private func refreshCurrentDate() {
        let now = Date()
        currentDateReference = now
        if TrajectoryMath.isToday(selectedDate, now: now) {
            selectedDate = now
        }
    }

    // MARK: - Bottom Floating Controls Bar

    private var bottomControlsBar: some View {
        HStack(spacing: 12) {
            // Recenter Button
            Button(action: {
                recenterTrigger += 1
            }) {
                Image(systemName: "location.north.line.fill")
                    .font(.body.bold())
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
            }
            .accessibilityLabel("Recenter Map")

            // Date Capsule with scrubbing gesture and tap picker
            dateScrubbingCapsule

            // Settings Button
            Button(action: {
                isSettingsPresented = true
            }) {
                Image(systemName: "gearshape")
                    .font(.body.bold())
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
            }
            .accessibilityLabel("Settings")
        }
    }

    private var dateScrubbingCapsule: some View {
        HStack(spacing: 8) {
            Button(action: {
                selectedDate = TrajectoryMath.previousDay(from: selectedDate)
                selectedItemID = nil
            }) {
                Image(systemName: "chevron.left")
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                    .padding(8)
            }
            .accessibilityLabel("Previous Day")

            Spacer()

            Button(action: {
                isDatePickerPresented = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formattedDateTitle(selectedDate))
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                }
            }
            .accessibilityLabel("Select Date")

            Spacer()

            Button(action: {
                if canGoNext {
                    selectedDate = TrajectoryMath.nextDay(from: selectedDate)
                    selectedItemID = nil
                }
            }) {
                Image(systemName: "chevron.right")
                    .font(.subheadline.bold())
                    .foregroundColor(canGoNext ? .primary : .secondary.opacity(0.4))
                    .padding(8)
            }
            .disabled(!canGoNext)
            .accessibilityLabel("Next Day")
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.width < -30 && canGoNext {
                        selectedDate = TrajectoryMath.nextDay(from: selectedDate)
                        selectedItemID = nil
                    } else if value.translation.width > 30 {
                        selectedDate = TrajectoryMath.previousDay(from: selectedDate)
                        selectedItemID = nil
                    }
                }
        )
    }

    private func formattedDateTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
    }
}

/// Dynamic SwiftData container that executes a predicate query strictly for the selected calendar day.
public struct DailyTrajectoryContainerView: View {
    let selectedDate: Date
    let currentDateReference: Date
    @Binding var mapDisplayMode: MapDisplayMode
    let recenterTrigger: Int
    let showDebugOverlay: Bool
    @Binding var selectedItemID: String?
    @Binding var isDetailPresented: Bool
    @Binding var isSettingsPresented: Bool

    @Query private var dayPoints: [LocationPoint]

    @ObservedObject private var locationManager = LocationManager.shared
    @AppStorage(LocationManager.trackingEnabledKey) private var isTrackingEnabled: Bool = true
    @AppStorage("showDiagnosticsMapOverlay") private var isDebugOverlayEnabled: Bool = false

    public init(
        selectedDate: Date,
        currentDateReference: Date = Date(),
        mapDisplayMode: Binding<MapDisplayMode> = .constant(.path),
        recenterTrigger: Int = 0,
        showDebugOverlay: Bool = false,
        selectedItemID: Binding<String?> = .constant(nil),
        isDetailPresented: Binding<Bool> = .constant(false),
        isSettingsPresented: Binding<Bool> = .constant(false),
        calendar: Calendar = .current
    ) {
        self.selectedDate = selectedDate
        self.currentDateReference = currentDateReference
        self._mapDisplayMode = mapDisplayMode
        self.recenterTrigger = recenterTrigger
        self.showDebugOverlay = showDebugOverlay
        self._selectedItemID = selectedItemID
        self._isDetailPresented = isDetailPresented
        self._isSettingsPresented = isSettingsPresented

        let interval = TrajectoryMath.dayInterval(for: selectedDate, calendar: calendar)
        let start = interval.start
        let end = interval.end

        self._dayPoints = Query(
            filter: #Predicate<LocationPoint> { point in
                point.timestamp >= start && point.timestamp < end
            },
            sort: \LocationPoint.timestamp,
            order: .forward
        )
    }

    public var body: some View {
        let trajectoryPoints = dayPoints.map {
            TrajectoryPoint(
                latitude: $0.latitude,
                longitude: $0.longitude,
                timestamp: $0.timestamp,
                horizontalAccuracy: $0.horizontalAccuracy,
                altitude: $0.altitude,
                verticalAccuracy: $0.verticalAccuracy,
                speed: $0.speed,
                speedAccuracy: $0.speedAccuracy,
                course: $0.course,
                courseAccuracy: $0.courseAccuracy,
                floor: $0.floor,
                sourceProvider: $0.sourceProvider,
                isSimulatedBySoftware: $0.isSimulatedBySoftware,
                isProducedByAccessory: $0.isProducedByAccessory,
                receivedTimestamp: $0.receivedTimestamp,
                sessionID: $0.sessionID,
                isBackground: $0.isBackground
            )
        }

        let history = DayHistory.build(
            points: trajectoryPoints,
            selectedDate: selectedDate,
            now: currentDateReference
        )
        let dayKey = String(Int64(TrajectoryMath.dayInterval(for: selectedDate).start.timeIntervalSince1970))

        let selectedStay = history.stays.first(where: { $0.id == selectedItemID })
        let selectedSegment = history.movingSegments.first(where: { $0.id == selectedItemID })
        let selectedObs: TrajectoryPoint? = {
            guard let id = selectedItemID, id.hasPrefix("obs_") else { return nil }
            return history.singleObservations.first(where: {
                let tsMs = Int64($0.timestamp.timeIntervalSince1970 * 1000)
                return "obs_\(tsMs)" == id
            })
        }()
        let selectedDebugPoint: (point: TrajectoryPoint, gap: TimeInterval?)? = {
            guard let id = selectedItemID, id.hasPrefix("raw_") else { return nil }
            let sorted = trajectoryPoints.sorted { $0.timestamp < $1.timestamp }
            for i in 0..<sorted.count {
                let pt = sorted[i]
                let tsMs = Int64(pt.timestamp.timeIntervalSince1970 * 1000)
                let lat = String(format: "%.5f", pt.latitude)
                let lon = String(format: "%.5f", pt.longitude)
                let testID = "raw_\(tsMs)_\(lat)_\(lon)"
                if testID == id {
                    let gap = (i > 0) ? pt.timestamp.timeIntervalSince(sorted[i - 1].timestamp) : nil
                    return (pt, gap)
                }
            }
            return nil
        }()

        ZStack(alignment: .top) {
            // Map
            TrajectoryMapView(
                segments: history.movingSegments,
                stays: history.stays,
                singleObservations: history.singleObservations,
                singletons: [],
                rawPoints: trajectoryPoints,
                displayMode: mapDisplayMode,
                showDebugOverlay: showDebugOverlay,
                dayKey: dayKey,
                recenterTrigger: recenterTrigger,
                selectedItemID: $selectedItemID
            )

            // Top Summary Bar & Mode Toggle
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    // Summary Capsule (Tapping opens Day Detail)
                    Button(action: {
                        isDetailPresented = true
                    }) {
                        HStack(spacing: 8) {
                            summaryPillContent(history: history)
                            Image(systemName: "chevron.right")
                                .font(.caption2.bold())
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
                    }
                    .accessibilityLabel("Day Summary: \(DayHistory.formatDistance(history.observedDistanceMeters)), \(history.places.count) places")

                    Spacer()

                    // Path | Time Toggle
                    Picker("Display Mode", selection: $mapDisplayMode) {
                        ForEach(MapDisplayMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 130)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)
                }
                .padding(.horizontal, 16)
                .padding(.top, 58)
            }
        }
        .sheet(isPresented: $isDetailPresented) {
            DayDetailView(history: history)
        }
        .sheet(isPresented: $isSettingsPresented) {
            UserSettingsView(
                analysis: TrajectoryMath.analyzeDay(points: trajectoryPoints),
                selectedDate: selectedDate,
                isTrackingEnabled: $isTrackingEnabled,
                showDebugOverlay: $isDebugOverlayEnabled
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: Binding(
            get: { selectedItemID != nil && (selectedStay != nil || selectedSegment != nil || selectedObs != nil || selectedDebugPoint != nil) },
            set: { if !$0 { selectedItemID = nil } }
        )) {
            if let stay = selectedStay {
                StayDetailCardView(stay: stay)
                    .presentationDetents([.fraction(0.24), .medium])
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            } else if let segment = selectedSegment {
                SegmentDetailCardView(segment: segment)
                    .presentationDetents([.fraction(0.24), .medium])
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            } else if let obs = selectedObs {
                SingleObservationDetailCardView(point: obs)
                    .presentationDetents([.fraction(0.20), .medium])
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            } else if let debugInfo = selectedDebugPoint {
                DebugPointDetailCardView(point: debugInfo.point, gapFromPrevious: debugInfo.gap)
                    .presentationDetents([.fraction(0.28), .medium])
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
        }
    }

    @ViewBuilder
    private func summaryPillContent(history: DayHistory) -> some View {
        if history.observedDistanceMeters > 0 || !history.places.isEmpty {
            Text("\(DayHistory.formatDistance(history.observedDistanceMeters)) · \(history.places.count) \(history.places.count == 1 ? "place" : "places") · \(DayHistory.formatDuration(history.movingDuration))")
                .font(.footnote.bold())
                .foregroundColor(.primary)
        } else if !history.singleObservations.isEmpty {
            Text("1 fix recorded")
                .font(.footnote.bold())
                .foregroundColor(.secondary)
        } else {
            Text("No activity recorded")
                .font(.footnote.bold())
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Tap Detail Cards

/// Clean card displaying neutral place details for a tapped stay.
public struct StayDetailCardView: View {
    public let stay: DayStay

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(.orange)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stay.assignedPlaceLabel ?? "Stationary Dwell")
                        .font(.headline)
                    Text(DayHistory.formatObservedBounds(start: stay.arrivalDate, end: stay.departureDate))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 20) {
                HStack(spacing: 6) {
                    Image(systemName: "hourglass")
                        .foregroundColor(.secondary)
                    Text(DayHistory.formatDuration(stay.duration))
                        .font(.subheadline.bold())
                }

                HStack(spacing: 6) {
                    Image(systemName: "scope")
                        .foregroundColor(.secondary)
                    Text(String(format: "±%.1fm accuracy", stay.horizontalAccuracy))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Clean card displaying details for a tapped moving trajectory segment.
public struct SegmentDetailCardView: View {
    public let segment: TrajectorySegment

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "figure.walk.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Moving Trajectory")
                        .font(.headline)
                    Text(DayHistory.formatObservedBounds(start: segment.startDate, end: segment.endDate))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 20) {
                HStack(spacing: 6) {
                    Image(systemName: "figure.walk")
                        .foregroundColor(.secondary)
                    Text(DayHistory.formatDistance(segment.distanceMeters))
                        .font(.subheadline.bold())
                }

                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .foregroundColor(.secondary)
                    Text(DayHistory.formatDuration(segment.duration))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Clean card displaying an isolated observation without inferred stay duration.
public struct SingleObservationDetailCardView: View {
    public let point: TrajectoryPoint

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "smallcircle.filled.circle")
                    .foregroundColor(.gray)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Single Observation")
                        .font(.headline)
                    Text("Observed at \(point.timestamp.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 16) {
                Text(String(format: "±%.1fm accuracy", point.horizontalAccuracy))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("No stay duration inferred")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Diagnostic bottom card presenting per-point evidence when inspecting raw points in debug mode.
public struct DebugPointDetailCardView: View {
    public let point: TrajectoryPoint
    public let gapFromPrevious: TimeInterval?

    private var statusBadge: (text: String, color: Color) {
        if !TrajectoryMath.isValid(point: point, maxHorizontalAccuracy: TrajectoryMath.defaultMaxHorizontalAccuracy) {
            return ("Outlier (>200m)", .red)
        } else if point.horizontalAccuracy > TrajectoryMath.defaultSuspiciousAccuracyThreshold {
            return ("Suspicious (100–200m)", .orange)
        } else {
            return ("Usable", .green)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(point.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.headline)
                Spacer()
                Text(statusBadge.text)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusBadge.color.opacity(0.15))
                    .foregroundColor(statusBadge.color)
                    .clipShape(Capsule())
            }

            HStack(spacing: 16) {
                Text(String(format: "Acc: ±%.1fm", point.horizontalAccuracy))
                    .font(.subheadline)
                if let gap = gapFromPrevious {
                    Text(String(format: "dt: +%.1fs", gap))
                        .font(.subheadline)
                        .foregroundColor(gap > TrajectoryMath.defaultMaxTimeGapSeconds ? .red : .secondary)
                }
                if let spd = point.speed, spd >= 0 {
                    Text(String(format: "Speed: %.1fm/s", spd))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - User Settings & Sequestered Developer Diagnostics

/// Clean user-facing settings view.
public struct UserSettingsView: View {
    public let analysis: TrajectoryDayAnalysis
    public let selectedDate: Date
    @Binding public var isTrackingEnabled: Bool
    @Binding public var showDebugOverlay: Bool
    @ObservedObject private var locationManager = LocationManager.shared
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            Form {
                Section("Tracking") {
                    Toggle("Background Recording", isOn: $isTrackingEnabled)
                    LabeledContent("Status", value: authStatusText)
                    LabeledContent("Precision", value: accuracyText)
                    if locationManager.isReducedAccuracy {
                        Button("Request Full Accuracy") {
                            locationManager.requestFullAccuracy()
                        }
                    }
                }

                Section {
                    NavigationLink(destination: DeveloperDiagnosticsView(
                        analysis: analysis,
                        selectedDate: selectedDate,
                        showDebugOverlay: $showDebugOverlay
                    )) {
                        HStack {
                            Image(systemName: "wrench.and.screwdriver")
                                .foregroundColor(.secondary)
                            Text("Developer Diagnostics")
                        }
                    }
                }
            }
            .navigationTitle("Settings")
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

    private var authStatusText: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways: return "Always Authorized"
        case .authorizedWhenInUse: return "When In Use"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not Determined"
        @unknown default: return "Unknown"
        }
    }

    private var accuracyText: String {
        if #available(iOS 14.0, *) {
            return locationManager.coreLocationManager.accuracyAuthorization == .fullAccuracy ? "Full Accuracy" : "Reduced Accuracy"
        }
        return "Standard"
    }
}

/// Hidden Developer Diagnostics view sequestered away from normal user UI.
public struct DeveloperDiagnosticsView: View {
    public let analysis: TrajectoryDayAnalysis
    public let selectedDate: Date
    @Binding public var showDebugOverlay: Bool
    @ObservedObject private var locationManager = LocationManager.shared

    public var body: some View {
        Form {
            Section("Diagnostics Map Overlay") {
                Toggle("Show Raw Points Overlay", isOn: $showDebugOverlay)
            }

            Section("Day Fixes (\(selectedDate.formatted(date: .abbreviated, time: .omitted)))") {
                LabeledContent("Raw Fixes Ingested", value: "\(analysis.rawCount)")
                LabeledContent("Usable Fixes (≤100m)", value: "\(analysis.usableCount)")
                LabeledContent("Suspicious (100–200m)", value: "\(analysis.suspiciousCount)")
                LabeledContent("Outliers (>200m / NaN)", value: "\(analysis.outlierCount)")
                LabeledContent("Moving Segments", value: "\(analysis.segments.count)")
                LabeledContent("Preserved Dwells/Singletons", value: "\(analysis.singletons.count)")
                LabeledContent("Timeline Gaps (>30s)", value: "\(analysis.gapCount)")
                if analysis.gapCount > 0 {
                    let gapStr = analysis.maxGapSeconds >= 60.0
                        ? String(format: "%.1f min", analysis.maxGapSeconds / 60.0)
                        : String(format: "%.0fs", analysis.maxGapSeconds)
                    LabeledContent("Max Gap Duration", value: gapStr)
                }
                LabeledContent("Median Accuracy", value: String(format: "%.1f m", analysis.medianAccuracy))
                LabeledContent("Worst Accuracy", value: String(format: "%.1f m", analysis.worstAccuracy))
                LabeledContent("Lifecycle Breakdown", value: "\(analysis.backgroundCount) bg / \(analysis.foregroundCount) fg / \(analysis.unknownLifecycleCount) unk")
            }

            Section("Sensor Health") {
                LabeledContent("Transient Errors", value: "\(locationManager.locationUnknownCount) locationUnknown events")
                if let lastDate = locationManager.lastLocationUnknownDate {
                    LabeledContent("Last Signal Search", value: lastDate.formatted(date: .omitted, time: .shortened))
                }
                LabeledContent("Active Session ID", value: String(locationManager.sessionID.prefix(8)))
            }
        }
        .navigationTitle("Developer Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }
}
