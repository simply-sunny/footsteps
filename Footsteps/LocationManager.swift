import Foundation
import CoreLocation
import SwiftData
import Combine

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    static let trackingEnabledKey = "isBackgroundTrackingEnabled"

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var lastError: String? = nil
    @Published private(set) var isTrackingActive: Bool = false

    private let locationManager: CLLocationManager
    private var modelContainer: ModelContainer?
    private var isConfigured = false

    var isTrackingEnabled: Bool {
        if UserDefaults.standard.object(forKey: Self.trackingEnabledKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: Self.trackingEnabledKey)
    }

    override init() {
        self.locationManager = CLLocationManager()
        super.init()
        self.locationManager.delegate = self
        self.authorizationStatus = locationManager.authorizationStatus
    }

    static func shouldStartTracking(
        isEnabled: Bool,
        authorizationStatus: CLAuthorizationStatus,
        isAlreadyTracking: Bool
    ) -> Bool {
        guard isEnabled else { return false }
        guard !isAlreadyTracking else { return false }
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse, .notDetermined:
            return true
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    func configure(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        guard !isConfigured else { return }
        isConfigured = true
        requestPermissions()
        if isTrackingEnabled {
            startTracking()
        }
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

    func setTrackingEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.trackingEnabledKey)
        if enabled {
            startTracking()
        } else {
            stopTracking()
        }
    }

    func startTracking() {
        guard Self.shouldStartTracking(
            isEnabled: isTrackingEnabled,
            authorizationStatus: authorizationStatus,
            isAlreadyTracking: isTrackingActive
        ) else { return }

        isTrackingActive = true
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

    func stopTracking() {
        guard isTrackingActive else { return }
        isTrackingActive = false

        locationManager.stopUpdatingLocation()
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            locationManager.stopMonitoringSignificantLocationChanges()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let validLocations = locations.filter { loc in
            TrajectoryMath.isValid(
                latitude: loc.coordinate.latitude,
                longitude: loc.coordinate.longitude,
                horizontalAccuracy: loc.horizontalAccuracy
            )
        }
        guard !validLocations.isEmpty else { return }

        Task { @MainActor in
            guard self.isTrackingEnabled else { return }
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
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                if self.isTrackingEnabled {
                    self.startTracking()
                }
            case .denied, .restricted:
                self.stopTracking()
            case .notDetermined:
                break
            @unknown default:
                break
            }
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
                    self.stopTracking()
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
