import SwiftUI
import SwiftData
import CoreLocation

struct DailyTrackerView: View {
    @ObservedObject private var locationManager = LocationManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedDate: Date = Date()
    @State private var currentDateReference: Date = Date()

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: selectedDate)
    }

    private var canGoNext: Bool {
        HeatmapGridMath.canNavigateNext(from: selectedDate, now: currentDateReference)
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
                    selectedDate = HeatmapGridMath.previousDay(from: selectedDate)
                }) {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .padding(8)
                }
                .accessibilityLabel("Previous Day")

                Spacer()

                Text(formattedDate)
                    .font(.headline)

                Spacer()

                Button(action: {
                    if canGoNext {
                        selectedDate = HeatmapGridMath.nextDay(from: selectedDate)
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .padding(8)
                }
                .disabled(!canGoNext)
                .accessibilityLabel("Next Day")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(UIColor.secondarySystemBackground))

            // Map content with predicate-filtered SwiftData query
            DailyHeatmapContainerView(selectedDate: selectedDate)
                .edgesIgnoringSafeArea(.bottom)
        }
        .onChange(of: scenePhase) { newPhase in
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
        if HeatmapGridMath.isToday(selectedDate, now: now) {
            selectedDate = now
        }
    }
}

/// Dynamic SwiftData container that executes a predicate query strictly for the selected calendar day.
struct DailyHeatmapContainerView: View {
    let selectedDate: Date
    @Query private var dayPoints: [LocationPoint]

    init(selectedDate: Date, calendar: Calendar = .current) {
        self.selectedDate = selectedDate
        let interval = HeatmapGridMath.dayInterval(for: selectedDate, calendar: calendar)
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
        HeatmapMapView(points: dayPoints, selectedDate: selectedDate)
    }
}
