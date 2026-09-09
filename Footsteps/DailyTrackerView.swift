import SwiftUI
import SwiftData
import CoreLocation

struct DailyTrackerView: View {
    @ObservedObject private var locationManager = LocationManager.shared
    @AppStorage(LocationManager.trackingEnabledKey) private var isTrackingEnabled: Bool = true
    @AppStorage("showDiagnosticsMapOverlay") private var showDebugOverlay: Bool = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedDate: Date = Date()
    @State private var currentDateReference: Date = Date()
    @State private var selectedItemID: String? = nil
    @State private var isSettingsPresented: Bool = false

    private var canGoNext: Bool {
        TrajectoryMath.canNavigateNext(from: selectedDate, now: currentDateReference)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Storage / tracking error banner
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
                .background(Color.red.opacity(0.15))
            }

            // Permissions & Precision Recovery Banners
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
                .background(Color.blue.opacity(0.1))
            } else if locationManager.authorizationStatus == .authorizedWhenInUse {
                HStack(spacing: 8) {
                    Image(systemName: "location.fill")
                        .foregroundColor(.blue)
                    Text("Upgrade to Always authorization for background recording.")
                        .font(.footnote)
                    Spacer()
                    Button("Upgrade") {
                        locationManager.requestPermissions()
                    }
                    .font(.footnote.bold())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
            } else if locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
                HStack(spacing: 8) {
                    Image(systemName: "location.slash.fill")
                        .foregroundColor(.red)
                    Text("Location access is disabled. Enable in Settings.")
                        .font(.footnote)
                    Spacer()
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        Link("Settings", destination: settingsURL)
                            .font(.footnote.bold())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.15))
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
                .background(Color.orange.opacity(0.15))
            }

            // Date Navigation Header
            HStack {
                Button(action: {
                    selectedDate = TrajectoryMath.previousDay(from: selectedDate)
                    selectedItemID = nil
                }) {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .padding(8)
                }
                .accessibilityLabel("Previous Day")

                Spacer()

                DatePicker(
                    "Select Date",
                    selection: $selectedDate,
                    in: ...currentDateReference,
                    displayedComponents: .date
                )
                .labelsHidden()

                Spacer()

                Button(action: {
                    if canGoNext {
                        selectedDate = TrajectoryMath.nextDay(from: selectedDate)
                        selectedItemID = nil
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .padding(8)
                }
                .disabled(!canGoNext)
                .accessibilityLabel("Next Day")

                Button(action: {
                    isSettingsPresented = true
                }) {
                    Image(systemName: "gearshape")
                        .font(.headline)
                        .padding(8)
                }
                .accessibilityLabel("Settings")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(UIColor.secondarySystemBackground))

            // Map content with predicate-filtered SwiftData query
            DailyTrajectoryContainerView(
                selectedDate: selectedDate,
                selectedItemID: $selectedItemID,
                isSettingsPresented: $isSettingsPresented,
                showDebugOverlay: showDebugOverlay
            )
            .id(TrajectoryMath.dayInterval(for: selectedDate).start)
            .animation(nil, value: selectedDate)
            .edgesIgnoringSafeArea(.bottom)
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
}

/// Dynamic SwiftData container that executes a predicate query strictly for the selected calendar day.
struct DailyTrajectoryContainerView: View {
    let selectedDate: Date
    @Binding var selectedItemID: String?
    @Binding var isSettingsPresented: Bool
    let showDebugOverlay: Bool
    @Query private var dayPoints: [LocationPoint]

    @ObservedObject private var locationManager = LocationManager.shared
    @AppStorage(LocationManager.trackingEnabledKey) private var isTrackingEnabled: Bool = true
    @AppStorage("showDiagnosticsMapOverlay") private var isDebugOverlayEnabled: Bool = false
    @State private var stepCount: Int? = nil
    @State private var isLoadingSteps: Bool = false
    @State private var queryTask: Task<Void, Never>? = nil

    init(
        selectedDate: Date,
        selectedItemID: Binding<String?> = .constant(nil),
        isSettingsPresented: Binding<Bool> = .constant(false),
        showDebugOverlay: Bool = false,
        calendar: Calendar = .current
    ) {
        self.selectedDate = selectedDate
        self._selectedItemID = selectedItemID
        self._isSettingsPresented = isSettingsPresented
        self.showDebugOverlay = showDebugOverlay
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

    var body: some View {
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
        let dayAnalysis = TrajectoryMath.analyzeDay(points: trajectoryPoints)
        let dayKey = String(Int64(TrajectoryMath.dayInterval(for: selectedDate).start.timeIntervalSince1970))

        let selectedSegment = dayAnalysis.segments.first(where: { $0.id == selectedItemID })
        let selectedSingleton = dayAnalysis.singletons.first(where: { $0.id == selectedItemID })
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

        ZStack {
            TrajectoryMapView(
                segments: dayAnalysis.segments,
                singletons: dayAnalysis.singletons,
                rawPoints: trajectoryPoints,
                showDebugOverlay: showDebugOverlay,
                dayKey: dayKey,
                selectedSegmentID: $selectedItemID
            )

            if dayPoints.isEmpty {
                Text("No data for this day.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsAndDiagnosticsView(
                analysis: dayAnalysis,
                selectedDate: selectedDate,
                isTrackingEnabled: $isTrackingEnabled,
                showDebugOverlay: $isDebugOverlayEnabled
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: Binding(
            get: { selectedItemID != nil && (selectedSegment != nil || selectedSingleton != nil || selectedDebugPoint != nil) },
            set: { isPresented in
                if !isPresented {
                    selectedItemID = nil
                }
            }
        )) {
            if let segment = selectedSegment {
                SegmentDetailCardView(
                    segment: segment,
                    stepCount: stepCount,
                    isLoadingSteps: isLoadingSteps
                )
                .presentationDetents([.fraction(0.22), .medium])
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            } else if let singleton = selectedSingleton {
                SingletonDetailCardView(singleton: singleton)
                    .presentationDetents([.fraction(0.22), .medium])
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            } else if let debugInfo = selectedDebugPoint {
                DebugPointDetailCardView(point: debugInfo.point, gapFromPrevious: debugInfo.gap)
                    .presentationDetents([.fraction(0.28), .medium])
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
        }
        .onChange(of: selectedItemID) { _, newID in
            queryTask?.cancel()
            stepCount = nil

            guard let newID = newID,
                  let matchingSegment = dayAnalysis.segments.first(where: { $0.id == newID }) else {
                isLoadingSteps = false
                return
            }

            isLoadingSteps = true
            let start = matchingSegment.startDate
            let end = matchingSegment.endDate

            queryTask = Task {
                let count = await StepCountReader.shared.fetchStepCount(startDate: start, endDate: end)
                guard !Task.isCancelled, selectedItemID == newID else { return }
                self.stepCount = count
                self.isLoadingSteps = false
            }
        }
    }
}

/// Compact bottom card presenting exact details for the tapped trajectory segment.
struct SegmentDetailCardView: View {
    let segment: TrajectorySegment
    let stepCount: Int?
    let isLoadingSteps: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .foregroundColor(.accentColor)
                    .font(.subheadline)
                Text(StepCountReader.formatTimeInterval(start: segment.startDate, end: segment.endDate))
                    .font(.headline)
            }

            HStack(spacing: 24) {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .foregroundColor(.secondary)
                    Text(StepCountReader.formatDurationMinutes(segment.duration))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 6) {
                    Image(systemName: "figure.walk")
                        .foregroundColor(.secondary)
                    if isLoadingSteps {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text(StepCountReader.formatStepCount(stepCount))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Compact bottom card presenting details for an isolated singleton or stationary dwell observation.
struct SingletonDetailCardView: View {
    let singleton: TrajectorySingleton

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(.accentColor)
                    .font(.subheadline)
                Text(singleton.point.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.headline)
                Text(singleton.observationDuration > 0 ? "Stationary Dwell" : "Isolated Fix")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 24) {
                HStack(spacing: 6) {
                    Image(systemName: "scope")
                        .foregroundColor(.secondary)
                    Text(String(format: "±%.1fm accuracy", singleton.point.horizontalAccuracy))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if singleton.observationDuration > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "hourglass")
                            .foregroundColor(.secondary)
                        Text(StepCountReader.formatDurationMinutes(singleton.observationDuration))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                if let alt = singleton.point.altitude {
                    HStack(spacing: 6) {
                        Image(systemName: "mountain.2")
                            .foregroundColor(.secondary)
                        Text(String(format: "%.0fm alt", alt))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Diagnostic bottom card presenting per-point evidence when inspecting raw points in debug mode.
struct DebugPointDetailCardView: View {
    let point: TrajectoryPoint
    let gapFromPrevious: TimeInterval?

    private var statusBadge: (text: String, color: Color) {
        if !TrajectoryMath.isValid(point: point, maxHorizontalAccuracy: TrajectoryMath.defaultMaxHorizontalAccuracy) {
            return ("Outlier (>200m)", .red)
        } else if point.horizontalAccuracy > TrajectoryMath.defaultSuspiciousAccuracyThreshold {
            return ("Suspicious (100–200m)", .orange)
        } else {
            return ("Usable", .green)
        }
    }

    var body: some View {
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

            HStack(spacing: 16) {
                let lifecycleText = (point.isBackground == true) ? "Background" : ((point.isBackground == false) ? "Foreground" : "Unknown Lifecycle")
                Text(lifecycleText)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if point.isSimulatedBySoftware == true {
                    Text("Software Simulated")
                        .font(.caption)
                        .foregroundColor(.purple)
                }
                if point.isProducedByAccessory == true {
                    Text("Accessory Source")
                        .font(.caption)
                        .foregroundColor(.indigo)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Settings and diagnostic sheet presenting tracking preferences, permissions, and live telemetry.
struct SettingsAndDiagnosticsView: View {
    let analysis: TrajectoryDayAnalysis
    let selectedDate: Date
    @Binding var isTrackingEnabled: Bool
    @Binding var showDebugOverlay: Bool
    @ObservedObject private var locationManager = LocationManager.shared
    @Environment(\.dismiss) private var dismiss

    private var authStatusText: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways: return "Always"
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Tracking & Permissions") {
                    Toggle("Background Tracking", isOn: $isTrackingEnabled)
                    LabeledContent("Authorization", value: authStatusText)
                    LabeledContent("Precision", value: accuracyText)
                    if locationManager.isReducedAccuracy {
                        Button("Request Full Accuracy") {
                            locationManager.requestFullAccuracy()
                        }
                    }
                    LabeledContent("Active Session", value: String(locationManager.sessionID.prefix(8)))
                }

                Section("Diagnostics Map Overlay") {
                    Toggle("Show Diagnostics Map Overlay", isOn: $showDebugOverlay)
                }

                Section("Day Diagnostics (\(selectedDate.formatted(date: .abbreviated, time: .omitted)))") {
                    LabeledContent("Raw Fixes Recorded", value: "\(analysis.rawCount)")
                    LabeledContent("Usable Fixes", value: "\(analysis.usableCount)")
                    LabeledContent("Suspicious (100–200m)", value: "\(analysis.suspiciousCount)")
                    LabeledContent("Outliers (>200m / NaN)", value: "\(analysis.outlierCount)")
                    LabeledContent("Continuous Segments", value: "\(analysis.segments.count)")
                    LabeledContent("Preserved Singletons / Dwells", value: "\(analysis.singletons.count)")
                    LabeledContent("Gaps (>30s)", value: "\(analysis.gapCount)")
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

                Section("Sensor Telemetry & Health") {
                    LabeledContent("Transient CLErrors", value: "\(locationManager.locationUnknownCount) locationUnknown events")
                    if let lastDate = locationManager.lastLocationUnknownDate {
                        LabeledContent("Last Signal Search", value: lastDate.formatted(date: .omitted, time: .shortened))
                    }
                }

                if let error = locationManager.lastError {
                    Section("Diagnostics Alert") {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Settings & Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
