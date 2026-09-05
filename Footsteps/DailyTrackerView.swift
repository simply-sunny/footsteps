import SwiftUI
import SwiftData
import CoreLocation

struct DailyTrackerView: View {
    @ObservedObject private var locationManager = LocationManager.shared
    @AppStorage(LocationManager.trackingEnabledKey) private var isTrackingEnabled: Bool = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedDate: Date = Date()
    @State private var currentDateReference: Date = Date()
    @State private var selectedSegmentID: String? = nil
    @State private var isSettingsPresented: Bool = false

    private var canGoNext: Bool {
        TrajectoryMath.canNavigateNext(from: selectedDate, now: currentDateReference)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Error banner for storage / tracking errors
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

            // Permissions banner (staged requests & Settings recovery)
            switch locationManager.authorizationStatus {
            case .notDetermined:
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

            case .authorizedWhenInUse:
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

            case .denied, .restricted:
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

            case .authorizedAlways:
                EmptyView()

            @unknown default:
                EmptyView()
            }

            // Date Navigation Header
            HStack {
                Button(action: {
                    selectedDate = TrajectoryMath.previousDay(from: selectedDate)
                    selectedSegmentID = nil
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
                        selectedSegmentID = nil
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
            DailyTrajectoryContainerView(selectedDate: selectedDate, selectedSegmentID: $selectedSegmentID)
                .id(TrajectoryMath.dayInterval(for: selectedDate).start)
                .edgesIgnoringSafeArea(.bottom)
        }
        .sheet(isPresented: $isSettingsPresented) {
            NavigationStack {
                Form {
                    Toggle("Background Tracking", isOn: $isTrackingEnabled)
                }
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            isSettingsPresented = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .onChange(of: isTrackingEnabled) { _, isEnabled in
            locationManager.setTrackingEnabled(isEnabled)
        }
        .onChange(of: selectedDate) { _, _ in
            selectedSegmentID = nil
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                refreshCurrentDate()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            refreshCurrentDate()
        }
    }

    private func refreshCurrentDate() {
        let now = Date()
        currentDateReference = now
        // If viewing today, stay locked to today across midnight
        if TrajectoryMath.isToday(selectedDate, now: now) {
            selectedDate = now
        }
    }
}

/// Dynamic SwiftData container that executes a predicate query strictly for the selected calendar day.
struct DailyTrajectoryContainerView: View {
    let selectedDate: Date
    @Binding var selectedSegmentID: String?
    @Query private var dayPoints: [LocationPoint]

    @State private var stepCount: Int? = nil
    @State private var isLoadingSteps: Bool = false
    @State private var queryTask: Task<Void, Never>? = nil

    init(selectedDate: Date, selectedSegmentID: Binding<String?> = .constant(nil), calendar: Calendar = .current) {
        self.selectedDate = selectedDate
        self._selectedSegmentID = selectedSegmentID
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
                horizontalAccuracy: $0.horizontalAccuracy
            )
        }
        let segments = TrajectoryMath.segment(points: trajectoryPoints)
        let selectedSegment = segments.first(where: { $0.id == selectedSegmentID })

        ZStack {
            TrajectoryMapView(segments: segments, selectedSegmentID: $selectedSegmentID)

            if dayPoints.isEmpty {
                Text("No data for this day")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .sheet(isPresented: Binding(
            get: { selectedSegmentID != nil && selectedSegment != nil },
            set: { isPresented in
                if !isPresented {
                    selectedSegmentID = nil
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
            }
        }
        .onChange(of: selectedSegmentID) { _, newID in
            queryTask?.cancel()
            stepCount = nil

            guard let newID = newID,
                  let matchingSegment = segments.first(where: { $0.id == newID }) else {
                isLoadingSteps = false
                return
            }

            isLoadingSteps = true
            let start = matchingSegment.startDate
            let end = matchingSegment.endDate

            queryTask = Task {
                let count = await StepCountReader.shared.fetchStepCount(startDate: start, endDate: end)
                guard !Task.isCancelled, selectedSegmentID == newID else { return }
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
            // Localized start–end time
            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .foregroundColor(.accentColor)
                    .font(.subheadline)
                Text(StepCountReader.formatTimeInterval(start: segment.startDate, end: segment.endDate))
                    .font(.headline)
            }

            HStack(spacing: 24) {
                // Duration in minutes
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .foregroundColor(.secondary)
                    Text(StepCountReader.formatDurationMinutes(segment.duration))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Step count / Steps unavailable
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
