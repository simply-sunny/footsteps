import Foundation
import CoreLocation
import SwiftData
import Combine
import UIKit

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    static let trackingEnabledKey = "isBackgroundTrackingEnabled"

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var lastError: String? = nil
    @Published private(set) var isTrackingActive: Bool = false
    @Published var locationUnknownCount: Int = 0
    @Published var lastLocationUnknownDate: Date? = nil

    let sessionID: String = UUID().uuidString
    let coreLocationManager: CLLocationManager

    private var modelContainer: ModelContainer?
    private var isConfigured = false

    var isTrackingEnabled: Bool {
        if UserDefaults.standard.object(forKey: Self.trackingEnabledKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: Self.trackingEnabledKey)
    }

    var isReducedAccuracy: Bool {
        if #available(iOS 14.0, *) {
            return coreLocationManager.accuracyAuthorization == .reducedAccuracy
        }
        return false
    }

    override init() {
        self.coreLocationManager = CLLocationManager()
        super.init()
        self.coreLocationManager.delegate = self
        self.authorizationStatus = coreLocationManager.authorizationStatus
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

    func refreshAuthorizationStatus() {
        self.authorizationStatus = coreLocationManager.authorizationStatus
        if isTrackingEnabled && Self.shouldStartTracking(
            isEnabled: true,
            authorizationStatus: authorizationStatus,
            isAlreadyTracking: isTrackingActive
        ) {
            startTracking()
        }
    }

    func requestPermissions() {
        switch coreLocationManager.authorizationStatus {
        case .notDetermined:
            coreLocationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            coreLocationManager.requestAlwaysAuthorization()
        case .authorizedAlways:
            requestFullAccuracy()
        default:
            break
        }
    }

    func requestFullAccuracy() {
        if #available(iOS 14.0, *) {
            if coreLocationManager.accuracyAuthorization == .reducedAccuracy {
                coreLocationManager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "FullAccuracy")
            }
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
        coreLocationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        coreLocationManager.distanceFilter = kCLDistanceFilterNone
        coreLocationManager.activityType = .fitness
        coreLocationManager.allowsBackgroundLocationUpdates = true
        coreLocationManager.showsBackgroundLocationIndicator = true
        coreLocationManager.pausesLocationUpdatesAutomatically = false
        coreLocationManager.startUpdatingLocation()

        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            coreLocationManager.startMonitoringSignificantLocationChanges()
        }
    }

    func stopTracking() {
        guard isTrackingActive else { return }
        isTrackingActive = false

        coreLocationManager.stopUpdatingLocation()
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            coreLocationManager.stopMonitoringSignificantLocationChanges()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !locations.isEmpty else { return }

        Task { @MainActor in
            guard self.isTrackingEnabled else { return }
            guard let container = self.modelContainer else { return }
            let context = ModelContext(container)
            let isBg = UIApplication.shared.applicationState != .active
            let now = Date()

            for loc in locations {
                let isSimulated: Bool?
                let isProducedByAccessory: Bool?
                if #available(iOS 15.0, *) {
                    isSimulated = loc.sourceInformation?.isSimulatedBySoftware
                    isProducedByAccessory = loc.sourceInformation?.isProducedByAccessory
                } else {
                    isSimulated = nil
                    isProducedByAccessory = nil
                }

                // Preserve raw reported measurements directly from CoreLocation (including negative sentinels)
                let point = LocationPoint(
                    latitude: loc.coordinate.latitude,
                    longitude: loc.coordinate.longitude,
                    timestamp: loc.timestamp,
                    horizontalAccuracy: loc.horizontalAccuracy,
                    altitude: loc.altitude,
                    verticalAccuracy: loc.verticalAccuracy,
                    speed: loc.speed,
                    speedAccuracy: loc.speedAccuracy,
                    course: loc.course,
                    courseAccuracy: loc.courseAccuracy,
                    floor: loc.floor?.level,
                    sourceProvider: "CoreLocation",
                    isSimulatedBySoftware: isSimulated,
                    isProducedByAccessory: isProducedByAccessory,
                    receivedTimestamp: now,
                    sessionID: self.sessionID,
                    isBackground: isBg
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
                // Transient location error: CoreLocation was temporarily unable to obtain a location fix.
                Task { @MainActor in
                    self.locationUnknownCount += 1
                    self.lastLocationUnknownDate = Date()
                }
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
