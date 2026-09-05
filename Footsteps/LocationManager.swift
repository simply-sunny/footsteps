import Foundation
import CoreLocation
import SwiftData
import Combine

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var lastError: String? = nil

    private let locationManager: CLLocationManager
    private var modelContainer: ModelContainer?
    private var isConfigured = false

    override init() {
        self.locationManager = CLLocationManager()
        super.init()
        self.locationManager.delegate = self
        self.authorizationStatus = locationManager.authorizationStatus
    }

    func configure(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        guard !isConfigured else { return }
        isConfigured = true
        requestPermissions()
        startTracking()
    }

    func reportStartupError(_ message: String) {
        self.lastError = message
    }

    func requestPermissions() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    func startTracking() {
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 50.0
        locationManager.activityType = .other
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.startUpdatingLocation()

        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            locationManager.startMonitoringSignificantLocationChanges()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let validLocations = locations.filter { loc in
            HeatmapGridMath.isValid(
                latitude: loc.coordinate.latitude,
                longitude: loc.coordinate.longitude,
                horizontalAccuracy: loc.horizontalAccuracy
            )
        }
        guard !validLocations.isEmpty else { return }

        Task { @MainActor in
            guard let container = self.modelContainer else { return }
            let context = ModelContext(container)
            for loc in validLocations {
                let point = LocationPoint(
                    latitude: loc.coordinate.latitude,
                    longitude: loc.coordinate.longitude,
                    timestamp: loc.timestamp,
                    horizontalAccuracy: loc.horizontalAccuracy
                )
                context.insert(point)
            }
            do {
                try context.save()
            } catch {
                self.lastError = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError {
            switch clError.code {
            case .locationUnknown:
                // Transient location error: CoreLocation will continue acquiring coordinates.
                return
            case .denied:
                Task { @MainActor in
                    self.authorizationStatus = .denied
                    self.lastError = "Location tracking authorization denied."
                }
                return
            default:
                break
            }
        }
        Task { @MainActor in
            self.lastError = "Location error: \(error.localizedDescription)"
        }
    }
}
