# Task Brief: Task 1 — Storage, Location Tracking, App Lifecycle & Project Configuration

## Goal
Implement the data model, background location manager, locked-device SwiftData persistence, app lifecycle handler, and Xcode project configuration for Footsteps.

## Binding Requirements & Constraints
- **Platform & Toolchain**: iOS 17+, Swift 5 language mode (`SWIFT_VERSION = 5.0`) on Swift 6 toolchain.
- **Dependencies**: Zero external dependencies. System frameworks only (`SwiftUI`, `SwiftData`, `CoreLocation`, `Foundation`, `UIKit`).
- **Data Model**: `LocationPoint` with exactly 4 fields: `latitude` (Double), `longitude` (Double), `timestamp` (Date), `horizontalAccuracy` (Double).
- **Location Tracking Profile**:
  - `desiredAccuracy = kCLLocationAccuracyHundredMeters`
  - `distanceFilter = 50.0`
  - `activityType = .other`
  - `allowsBackgroundLocationUpdates = true` (`UIBackgroundModes: location` in `Info.plist`)
  - `pausesLocationUpdatesAutomatically = false`
  - Concurrent `startMonitoringSignificantLocationChanges()` registered for background relaunch recovery.
- **Lifecycle & Relaunch**: `AppDelegate` detects `UIApplication.LaunchOptionsKey.location` on launch and initializes `LocationManager.shared`.
- **Permissions Flow**: Staged progression (request When In Use, then Always upon authorization).
- **Storage Protection**: SwiftData store directory set to `FileProtectionType.completeUntilFirstUserAuthentication`. Save failures propagated/logged; no silent in-memory fallback.
- **Validation**: Filter out invalid coordinates (lat outside [-90, 90], lon outside [-180, 180]) and negative horizontal accuracy (< 0) before saving.

## Exact Shared Interfaces

```swift
// Footsteps/LocationPoint.swift
import Foundation
import SwiftData

@Model
public final class LocationPoint {
    public var latitude: Double
    public var longitude: Double
    public var timestamp: Date
    public var horizontalAccuracy: Double

    public init(latitude: Double, longitude: Double, timestamp: Date = Date(), horizontalAccuracy: Double = 0.0) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.horizontalAccuracy = horizontalAccuracy
    }
}
```

```swift
// Footsteps/HeatmapGridMath.swift
import Foundation

public struct DensityCell: Equatable {
    public let minLat: Double
    public let maxLat: Double
    public let minLon: Double
    public let maxLon: Double
    public let count: Int
    public let intensity: Double

    public init(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double, count: Int, intensity: Double) {
        self.minLat = minLat
        self.maxLat = maxLat
        self.minLon = minLon
        self.maxLon = maxLon
        self.count = count
        self.intensity = intensity
    }
}

public enum HeatmapGridMath {
    public static func isValid(latitude: Double, longitude: Double, horizontalAccuracy: Double) -> Bool {
        guard latitude >= -90.0 && latitude <= 90.0 else { return false }
        guard longitude >= -180.0 && longitude <= 180.0 else { return false }
        guard horizontalAccuracy >= 0.0 else { return false }
        return true
    }

    public static func dayInterval(for date: Date, calendar: Calendar = .current) -> DateInterval {
        let startOfDay = calendar.startOfDay(for: date)
        let nextStartOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(86400)
        return DateInterval(start: startOfDay, end: nextStartOfDay)
    }

    public static func isToday(_ date: Date, calendar: Calendar = .current, now: Date = Date()) -> Bool {
        calendar.isDate(date, inSameDayAs: now)
    }

    public static func computeDensityGrid(coordinates: [(latitude: Double, longitude: Double)], cellSizeDegrees: Double = 0.001) -> [DensityCell] {
        guard !coordinates.isEmpty, cellSizeDegrees > 0 else { return [] }
        var cellCounts: [String: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double, count: Int)] = [:]
        for coord in coordinates {
            guard isValid(latitude: coord.latitude, longitude: coord.longitude, horizontalAccuracy: 0) else { continue }
            let latIndex = Int(floor(coord.latitude / cellSizeDegrees))
            let lonIndex = Int(floor(coord.longitude / cellSizeDegrees))
            let key = "\(latIndex),\(lonIndex)"
            if var existing = cellCounts[key] {
                existing.count += 1
                cellCounts[key] = existing
            } else {
                let minLat = Double(latIndex) * cellSizeDegrees
                let maxLat = minLat + cellSizeDegrees
                let minLon = Double(lonIndex) * cellSizeDegrees
                let maxLon = minLon + cellSizeDegrees
                cellCounts[key] = (minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon, count: 1)
            }
        }
        let maxCount = cellCounts.values.map(\.count).max() ?? 1
        return cellCounts.values.map { cell in
            let intensity = maxCount > 0 ? Double(cell.count) / Double(maxCount) : 1.0
            return DensityCell(minLat: cell.minLat, maxLat: cell.maxLat, minLon: cell.minLon, maxLon: cell.maxLon, count: cell.count, intensity: intensity)
        }
    }
}
```

```swift
// Footsteps/LocationManager.swift
import Foundation
import CoreLocation
import SwiftData
import Combine

@MainActor
public final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    public static let shared = LocationManager()
    @Published public var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published public var lastError: String? = nil
    public func configure(modelContainer: ModelContainer)
    public func requestPermissions()
    public func startTracking()
}
```

## Files to Create
1. `Footsteps/Info.plist`: Background modes (`location`), usage descriptions (`NSLocationWhenInUseUsageDescription`, `NSLocationAlwaysAndWhenInUseUsageDescription`).
2. `Footsteps/HeatmapGridMath.swift`: Coordinate validation and DST day interval math.
3. `Footsteps/LocationPoint.swift`: SwiftData `@Model`.
4. `Footsteps/LocationManager.swift`: Location delegate and background tracking.
5. `Footsteps/FootstepsApp.swift`: App entry point and `AppDelegateAdaptor`.
6. `Footsteps.xcodeproj/project.pbxproj`: Project configuration targeting iOS 17+.
7. `Tests/Task1FoundationTests.swift`: Pure Foundation logic test runner.
8. `Tests/LocationAndStorageTests.swift`: XCTest persistence and lifecycle tests.

## Verification
```bash
swiftc Tests/Task1FoundationTests.swift Footsteps/HeatmapGridMath.swift -o /tmp/task1_test && /tmp/task1_test
```
