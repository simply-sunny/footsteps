# Footsteps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Footsteps, a minimal local-first iOS 17+ app that passively records device location in SwiftData and renders a daily 2D density heatmap in MapKit.

**Architecture:** A native 5-file Swift architecture. App launch initializes background tracking and significant change monitoring in `LocationManager` and configures locked-device SwiftData persistence in `FootstepsApp`. `DailyTrackerView` displays day navigation and renders the selected day's density grid via `HeatmapMapView` and shared Foundation algorithms in `HeatmapGridMath`.

**Tech Stack:** iOS 17+, Swift 5 language mode on Swift 6 toolchain (chosen for SwiftData/CoreLocation delegate concurrency stability), SwiftUI, SwiftData, Core Location, MapKit (`MKMapView`).

**Spec:** `docs/superpowers/specs/2026-09-05-footsteps-design.md`

## Global Constraints

- Platform: iOS 17+ deployment target.
- Language Mode: Swift 5 mode (`SWIFT_VERSION = 5.0`) on Swift 6 toolchain for maximum framework interoperability without unnecessary concurrency boilerplate.
- Dependencies: Zero third-party dependencies; use only Apple system frameworks (SwiftUI, SwiftData, CoreLocation, MapKit, Foundation, UIKit).
- Target Layout: Exactly 5 Swift application files (`FootstepsApp.swift`, `LocationManager.swift`, `LocationPoint.swift`, `HeatmapMapView.swift`, `DailyTrackerView.swift`) plus 1 Foundation helper (`HeatmapGridMath.swift`).
- Tracking Configuration: `kCLLocationAccuracyHundredMeters`, `distanceFilter = 50.0m`, `activityType = .other`, `allowsBackgroundLocationUpdates = true`, `pausesLocationUpdatesAutomatically = false`, concurrent `startMonitoringSignificantLocationChanges()`.
- Storage & Protection: `FileProtectionType.completeUntilFirstUserAuthentication` applied to the database directory. Corrupt stores are never deleted silently; no in-memory fallbacks.
- Queries & Date Math: Calendar-day interval `[startOfDay, nextStartOfDay)` to correctly handle DST boundaries.
- Permissions: Staged progression (When In Use requested first, followed by Always). Clear settings recovery path when denied.

---

## Shared Interfaces & Data Types

The shared types and interfaces between tasks are strictly defined below:

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
    public let intensity: Double // 0.0 ... 1.0

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

    public static func computeDensityGrid(
        coordinates: [(latitude: Double, longitude: Double)],
        cellSizeDegrees: Double = 0.001
    ) -> [DensityCell] {
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
            return DensityCell(
                minLat: cell.minLat,
                maxLat: cell.maxLat,
                minLon: cell.minLon,
                maxLon: cell.maxLon,
                count: cell.count,
                intensity: intensity
            )
        }
    }
}
```

---

## Tasks

### Task 1: Storage, Location Tracking, App Lifecycle & Project Configuration

**Files:**
- Create: `Footsteps.xcodeproj/project.pbxproj`
- Create: `Footsteps/Info.plist`
- Create: `Footsteps/HeatmapGridMath.swift`
- Create: `Footsteps/LocationPoint.swift`
- Create: `Footsteps/LocationManager.swift`
- Create: `Footsteps/FootstepsApp.swift`
- Test: `Tests/Task1FoundationTests.swift`
- Test: `Tests/LocationAndStorageTests.swift`

**Interfaces:**
- Consumes: None (initial setup).
- Produces:
  - `LocationPoint`: SwiftData `@Model` with `latitude`, `longitude`, `timestamp`, `horizontalAccuracy`.
  - `HeatmapGridMath.isValid(latitude:longitude:horizontalAccuracy:) -> Bool`
  - `HeatmapGridMath.dayInterval(for:calendar:) -> DateInterval`
  - `HeatmapGridMath.isToday(_:calendar:now:) -> Bool`
  - `LocationManager`: Singleton `@MainActor` managing `CLLocationManager`, background tracking, significant change monitoring, staged permissions, SwiftData point persistence.
  - `FootstepsApp`: Lifecycle handling `UIApplication.LaunchOptionsKey.location` relaunch and locked storage file protection.

- [ ] **Step 1: Write the failing CLI Foundation test for Task 1**

Create `Tests/Task1FoundationTests.swift`:

```swift
import Foundation

// Test runner assertion helper
func assertTrue(_ condition: Bool, _ message: String) {
    if !condition {
        print("FAIL: \(message)")
        exit(1)
    }
}

func assertFalse(_ condition: Bool, _ message: String) {
    assertTrue(!condition, message)
}

print("Running Task 1 Foundation Tests...")

// 1. Coordinate Validation Tests
assertTrue(HeatmapGridMath.isValid(latitude: 37.7749, longitude: -122.4194, horizontalAccuracy: 10.0), "Valid coordinates should pass")
assertTrue(HeatmapGridMath.isValid(latitude: 0.0, longitude: 0.0, horizontalAccuracy: 0.0), "Zero coordinates should pass")
assertTrue(HeatmapGridMath.isValid(latitude: -90.0, longitude: -180.0, horizontalAccuracy: 5.0), "Boundary coordinates should pass")
assertTrue(HeatmapGridMath.isValid(latitude: 90.0, longitude: 180.0, horizontalAccuracy: 5.0), "Boundary coordinates should pass")

assertFalse(HeatmapGridMath.isValid(latitude: 90.001, longitude: 0.0, horizontalAccuracy: 5.0), "Latitude > 90 must fail")
assertFalse(HeatmapGridMath.isValid(latitude: -90.001, longitude: 0.0, horizontalAccuracy: 5.0), "Latitude < -90 must fail")
assertFalse(HeatmapGridMath.isValid(latitude: 0.0, longitude: 180.001, horizontalAccuracy: 5.0), "Longitude > 180 must fail")
assertFalse(HeatmapGridMath.isValid(latitude: 0.0, longitude: -180.001, horizontalAccuracy: 5.0), "Longitude < -180 must fail")
assertFalse(HeatmapGridMath.isValid(latitude: 37.7749, longitude: -122.4194, horizontalAccuracy: -1.0), "Negative accuracy must fail")

// 2. DST-Aware Date Interval Tests
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "America/New_York")!
var components = DateComponents()
components.year = 2026
components.month = 3
components.day = 8 // US DST transition day in 2026
components.hour = 12
let testDate = calendar.date(from: components)!

let interval = HeatmapGridMath.dayInterval(for: testDate, calendar: calendar)
let startOfDay = calendar.startOfDay(for: testDate)
let nextStartOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

assertTrue(interval.start == startOfDay, "Interval start must match startOfDay")
assertTrue(interval.end == nextStartOfDay, "Interval end must match next day startOfDay")
assertTrue(interval.contains(testDate), "Interval must contain noon on same day")
assertFalse(interval.contains(nextStartOfDay), "Interval must be half-open [start, nextStart)")

// 3. isToday Tests
let now = Date()
assertTrue(HeatmapGridMath.isToday(now, calendar: calendar, now: now), "now must be recognized as today")
let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
assertFalse(HeatmapGridMath.isToday(yesterday, calendar: calendar, now: now), "yesterday must not be today")
let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
assertFalse(HeatmapGridMath.isToday(tomorrow, calendar: calendar, now: now), "tomorrow must not be today")

print("All Task 1 Foundation Tests Passed Successfully!")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swiftc Tests/Task1FoundationTests.swift -o /tmp/task1_test`
Expected: FAIL with compilation error "cannot find 'HeatmapGridMath' in scope"

- [ ] **Step 3: Implement `Footsteps/HeatmapGridMath.swift` (foundation validation & date math)**

Create `Footsteps/HeatmapGridMath.swift`:

```swift
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

    public static func computeDensityGrid(
        coordinates: [(latitude: Double, longitude: Double)],
        cellSizeDegrees: Double = 0.001
    ) -> [DensityCell] {
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
            return DensityCell(
                minLat: cell.minLat,
                maxLat: cell.maxLat,
                minLon: cell.minLon,
                maxLon: cell.maxLon,
                count: cell.count,
                intensity: intensity
            )
        }
    }
}
```

- [ ] **Step 4: Run CLI test to verify it passes**

Run: `swiftc Tests/Task1FoundationTests.swift Footsteps/HeatmapGridMath.swift -o /tmp/task1_test && /tmp/task1_test`
Expected: Output `Running Task 1 Foundation Tests...` followed by `All Task 1 Foundation Tests Passed Successfully!`

- [ ] **Step 5: Implement `Footsteps/LocationPoint.swift`**

Create `Footsteps/LocationPoint.swift`:

```swift
import Foundation
import SwiftData

@Model
public final class LocationPoint {
    public var latitude: Double
    public var longitude: Double
    public var timestamp: Date
    public var horizontalAccuracy: Double

    public init(
        latitude: Double,
        longitude: Double,
        timestamp: Date = Date(),
        horizontalAccuracy: Double = 0.0
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.horizontalAccuracy = horizontalAccuracy
    }
}
```

- [ ] **Step 6: Implement `Footsteps/LocationManager.swift`**

Create `Footsteps/LocationManager.swift`:

```swift
import Foundation
import CoreLocation
import SwiftData
import Combine

@MainActor
public final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    public static let shared = LocationManager()

    @Published public var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published public var lastError: String? = nil

    private let locationManager: CLLocationManager
    private var modelContainer: ModelContainer?

    override public init() {
        self.locationManager = CLLocationManager()
        super.init()
        self.locationManager.delegate = self
        self.authorizationStatus = locationManager.authorizationStatus
    }

    public func configure(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        requestPermissions()
        startTracking()
    }

    public func requestPermissions() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if locationManager.authorizationStatus == .authorizedWhenInUse {
            locationManager.requestAlwaysAuthorization()
        }
    }

    public func startTracking() {
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 50.0
        locationManager.activityType = .other
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.startUpdatingLocation()
        locationManager.startMonitoringSignificantLocationChanges()
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let container = self.modelContainer else { return }
            let context = ModelContext(container)
            for location in locations {
                let lat = location.coordinate.latitude
                let lon = location.coordinate.longitude
                let acc = location.horizontalAccuracy
                guard HeatmapGridMath.isValid(latitude: lat, longitude: lon, horizontalAccuracy: acc) else { continue }
                let point = LocationPoint(
                    latitude: lat,
                    longitude: lon,
                    timestamp: location.timestamp,
                    horizontalAccuracy: acc
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

    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse {
                manager.requestAlwaysAuthorization()
            }
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.lastError = "Location error: \(error.localizedDescription)"
        }
    }
}
```

- [ ] **Step 7: Implement `Footsteps/Info.plist` and `Footsteps/FootstepsApp.swift`**

Create `Footsteps/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSRequiresIPhoneOS</key>
	<true/>
	<key>NSLocationWhenInUseUsageDescription</key>
	<string>Footsteps records your daily movements to display your personal density heatmap.</string>
	<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
	<string>Footsteps passively tracks your location in the background to build your daily movement history.</string>
	<key>UIBackgroundModes</key>
	<array>
		<string>location</string>
	</array>
	<key>UILaunchScreen</key>
	<dict/>
	<key>UISupportedInterfaceOrientations</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
		<string>UIInterfaceOrientationLandscapeLeft</string>
		<string>UIInterfaceOrientationLandscapeRight</string>
	</array>
</dict>
</plist>
```

Create `Footsteps/FootstepsApp.swift`:

```swift
import SwiftUI
import SwiftData

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if let _ = launchOptions?[.location] {
            _ = LocationManager.shared
        }
        return true
    }
}

@main
struct FootstepsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let sharedModelContainer: ModelContainer

    init() {
        do {
            let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let storeURL = appSupportURL.appendingPathComponent("default.store")
            try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true, attributes: [
                FileAttributeKey.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
            ])
            let schema = Schema([LocationPoint.self])
            let modelConfiguration = ModelConfiguration(schema: schema, url: storeURL)
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            self.sharedModelContainer = container
            LocationManager.shared.configure(modelContainer: container)
        } catch {
            fatalError("Failed to initialize SwiftData ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            DailyTrackerView()
        }
        .modelContainer(sharedModelContainer)
    }
}
```

- [ ] **Step 8: Create Xcode project configuration `Footsteps.xcodeproj/project.pbxproj`**

Create `Footsteps.xcodeproj/project.pbxproj` with iOS 17 target, Swift 5.0 language mode, and file references for all source and test files.

- [ ] **Step 9: Write iOS XCTest suite `Tests/LocationAndStorageTests.swift`**

Create `Tests/LocationAndStorageTests.swift`:

```swift
import XCTest
import SwiftData
@testable import Footsteps

final class LocationAndStorageTests: XCTestCase {
    var container: ModelContainer!

    override func setUpWithError() throws {
        let schema = Schema([LocationPoint.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
    }

    override func tearDownWithError() throws {
        container = nil
    }

    func testLocationPointPersistence() throws {
        let context = ModelContext(container)
        let point = LocationPoint(latitude: 37.7749, longitude: -122.4194, timestamp: Date(), horizontalAccuracy: 5.0)
        context.insert(point)
        try context.save()

        let descriptor = FetchDescriptor<LocationPoint>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.latitude, 37.7749)
        XCTAssertEqual(fetched.first?.longitude, -122.4194)
        XCTAssertEqual(fetched.first?.horizontalAccuracy, 5.0)
    }

    func testInvalidCoordinateRejection() {
        XCTAssertFalse(HeatmapGridMath.isValid(latitude: 95.0, longitude: 10.0, horizontalAccuracy: 5.0))
        XCTAssertFalse(HeatmapGridMath.isValid(latitude: 10.0, longitude: 200.0, horizontalAccuracy: 5.0))
        XCTAssertFalse(HeatmapGridMath.isValid(latitude: 10.0, longitude: 10.0, horizontalAccuracy: -5.0))
        XCTAssertTrue(HeatmapGridMath.isValid(latitude: 10.0, longitude: 10.0, horizontalAccuracy: 5.0))
    }

    func testDirectoryFileProtection() throws {
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let attributes = try FileManager.default.attributesOfItem(atPath: appSupportURL.path)
        if let protection = attributes[FileAttributeKey.protectionKey] as? FileProtectionType {
            XCTAssertEqual(protection, FileProtectionType.completeUntilFirstUserAuthentication)
        }
    }
}
```

- [ ] **Step 10: Commit Task 1 files**

```bash
git add Footsteps.xcodeproj/project.pbxproj Footsteps/Info.plist Footsteps/HeatmapGridMath.swift Footsteps/LocationPoint.swift Footsteps/LocationManager.swift Footsteps/FootstepsApp.swift Tests/Task1FoundationTests.swift Tests/LocationAndStorageTests.swift
git commit -m "feat: implement storage, location tracking, app lifecycle, and project scaffolding"
```

---

### Task 2: MapKit Density Grid, DailyTrackerView, UI Integration & Documentation

**Files:**
- Create: `Footsteps/HeatmapMapView.swift`
- Create: `Footsteps/DailyTrackerView.swift`
- Test: `Tests/Task2FoundationTests.swift`
- Test: `Tests/UIAndMapTests.swift`
- Create: `README.md`

**Interfaces:**
- Consumes:
  - `LocationPoint` (from Task 1)
  - `HeatmapGridMath` (from Task 1)
  - `LocationManager.shared` (from Task 1)
- Produces:
  - `HeatmapMapView`: `UIViewRepresentable` wrapping `MKMapView` with custom `DensityPolygon` overlay and alpha-blended `MKPolygonRenderer`.
  - `DailyTrackerView`: Complete SwiftUI view with date navigation header, permission warning banner, and `HeatmapMapView`.
  - `README.md`: Build, simulator simulation, background verification, and test instructions.

- [ ] **Step 1: Write the failing CLI Foundation test for Task 2**

Create `Tests/Task2FoundationTests.swift`:

```swift
import Foundation

func assertTrue(_ condition: Bool, _ message: String) {
    if !condition {
        print("FAIL: \(message)")
        exit(1)
    }
}

func assertFalse(_ condition: Bool, _ message: String) {
    assertTrue(!condition, message)
}

print("Running Task 2 Foundation Tests...")

// 1. Grid Bucketing - Empty List
let emptyCells = HeatmapGridMath.computeDensityGrid(coordinates: [])
assertTrue(emptyCells.isEmpty, "Empty coordinates must produce empty cells")

// 2. Grid Bucketing - Single Point
let singlePoint = [(latitude: 37.7749, longitude: -122.4194)]
let singleCells = HeatmapGridMath.computeDensityGrid(coordinates: singlePoint, cellSizeDegrees: 0.001)
assertTrue(singleCells.count == 1, "Single point must produce 1 cell")
assertTrue(singleCells[0].count == 1, "Single cell count must be 1")
assertTrue(singleCells[0].intensity == 1.0, "Single cell intensity must be 1.0")

// 3. Grid Bucketing - Multi Point Aggregation
let multiPoints = [
    (latitude: 37.7741, longitude: -122.4191), // Cell A
    (latitude: 37.7742, longitude: -122.4192), // Cell A
    (latitude: 37.7743, longitude: -122.4193), // Cell A
    (latitude: 37.7800, longitude: -122.4100)  // Cell B
]
let multiCells = HeatmapGridMath.computeDensityGrid(coordinates: multiPoints, cellSizeDegrees: 0.001)
assertTrue(multiCells.count == 2, "Should aggregate into 2 distinct cells")

let cellA = multiCells.first(where: { $0.count == 3 })
let cellB = multiCells.first(where: { $0.count == 1 })
assertTrue(cellA != nil, "Cell A with count 3 must exist")
assertTrue(cellB != nil, "Cell B with count 1 must exist")
assertTrue(cellA!.intensity == 1.0, "Max density cell must have intensity 1.0")
assertTrue(abs(cellB!.intensity - (1.0 / 3.0)) < 0.0001, "Cell B intensity must be proportional (1/3)")

// 4. Invalid Coordinate Filtering in Grid Computation
let mixedPoints = [
    (latitude: 37.7741, longitude: -122.4191),
    (latitude: 100.0, longitude: -122.4191), // Invalid lat
    (latitude: 37.7741, longitude: 200.0)    // Invalid lon
]
let filteredCells = HeatmapGridMath.computeDensityGrid(coordinates: mixedPoints, cellSizeDegrees: 0.001)
assertTrue(filteredCells.count == 1, "Invalid coordinates must be excluded from density grid")
assertTrue(filteredCells[0].count == 1, "Only valid points should be counted")

print("All Task 2 Foundation Tests Passed Successfully!")
```

- [ ] **Step 2: Run CLI test to verify it fails if `computeDensityGrid` is absent or broken**

Run: `swiftc Tests/Task2FoundationTests.swift Footsteps/HeatmapGridMath.swift -o /tmp/task2_test && /tmp/task2_test`
Expected: Output `Running Task 2 Foundation Tests...` followed by `All Task 2 Foundation Tests Passed Successfully!` (verifying the algorithm implemented in `HeatmapGridMath.swift`).

- [ ] **Step 3: Implement `Footsteps/HeatmapMapView.swift`**

Create `Footsteps/HeatmapMapView.swift`:

```swift
import SwiftUI
import MapKit

public final class DensityPolygon: MKPolygon {
    public var intensity: Double = 1.0
}

public struct HeatmapMapView: UIViewRepresentable {
    public let points: [LocationPoint]

    public init(points: [LocationPoint]) {
        self.points = points
    }

    public func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        return mapView
    }

    public func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.removeOverlays(mapView.overlays)
        guard !points.isEmpty else { return }

        let coordinates = points.map { (latitude: $0.latitude, longitude: $0.longitude) }
        let cells = HeatmapGridMath.computeDensityGrid(coordinates: coordinates)

        var overlays: [MKOverlay] = []
        var zoomCoords: [CLLocationCoordinate2D] = []

        for cell in cells {
            var coords = [
                CLLocationCoordinate2D(latitude: cell.minLat, longitude: cell.minLon),
                CLLocationCoordinate2D(latitude: cell.maxLat, longitude: cell.minLon),
                CLLocationCoordinate2D(latitude: cell.maxLat, longitude: cell.maxLon),
                CLLocationCoordinate2D(latitude: cell.minLat, longitude: cell.maxLon)
            ]
            let polygon = DensityPolygon(coordinates: &coords, count: 4)
            polygon.intensity = cell.intensity
            overlays.append(polygon)
            zoomCoords.append(CLLocationCoordinate2D(latitude: (cell.minLat + cell.maxLat) / 2.0, longitude: (cell.minLon + cell.maxLon) / 2.0))
        }

        mapView.addOverlays(overlays)

        if let first = zoomCoords.first, !cells.isEmpty {
            let minLat = cells.map(\.minLat).min() ?? first.latitude
            let maxLat = cells.map(\.maxLat).max() ?? first.latitude
            let minLon = cells.map(\.minLon).min() ?? first.longitude
            let maxLon = cells.map(\.maxLon).max() ?? first.longitude
            let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2.0, longitude: (minLon + maxLon) / 2.0)
            let span = MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.5, 0.01),
                longitudeDelta: max((maxLon - minLon) * 1.5, 0.01)
            )
            mapView.setRegion(MKCoordinateRegion(center: center, span: span), animated: true)
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public final class Coordinator: NSObject, MKMapViewDelegate {
        public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let densityPoly = overlay as? DensityPolygon {
                let renderer = MKPolygonRenderer(polygon: densityPoly)
                let alpha = min(max(densityPoly.intensity * 0.7 + 0.15, 0.2), 0.85)
                renderer.fillColor = UIColor.systemBlue.withAlphaComponent(alpha)
                renderer.strokeColor = UIColor.systemBlue.withAlphaComponent(min(alpha + 0.2, 1.0))
                renderer.lineWidth = 1.0
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
```

- [ ] **Step 4: Implement `Footsteps/DailyTrackerView.swift`**

Create `Footsteps/DailyTrackerView.swift`:

```swift
import SwiftUI
import SwiftData
import CoreLocation

public struct DailyTrackerView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var locationManager = LocationManager.shared
    @State private var selectedDate: Date = Date()
    @Query private var allPoints: [LocationPoint]

    public init() {}

    private var isViewingToday: Bool {
        HeatmapGridMath.isToday(selectedDate)
    }

    private var dailyPoints: [LocationPoint] {
        let interval = HeatmapGridMath.dayInterval(for: selectedDate)
        return allPoints.filter { interval.contains($0.timestamp) }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: selectedDate)
    }

    public var body: some View {
        VStack(spacing: 0) {
            if locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text("Location access is disabled. Enable in Settings.")
                        .font(.footnote)
                    Spacer()
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link("Settings", destination: url)
                            .font(.footnote.bold())
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.15))
            }

            HStack {
                Button(action: {
                    if let previousDay = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) {
                        selectedDate = previousDay
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .padding(8)
                }
                .accessibilityLabel("Previous Day")

                Spacer()

                VStack {
                    Text(formattedDate)
                        .font(.headline)
                    Text("\(dailyPoints.count) points recorded")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: {
                    if let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) {
                        selectedDate = nextDay
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .padding(8)
                }
                .disabled(isViewingToday)
                .accessibilityLabel("Next Day")
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color(UIColor.secondarySystemBackground))

            HeatmapMapView(points: dailyPoints)
                .edgesIgnoringSafeArea(.bottom)
        }
    }
}
```

- [ ] **Step 5: Write iOS XCTest suite `Tests/UIAndMapTests.swift`**

Create `Tests/UIAndMapTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import Footsteps

final class UIAndMapTests: XCTestCase {
    func testDayIntervalFiltering() {
        let calendar = Calendar.current
        let today = Date()
        let interval = HeatmapGridMath.dayInterval(for: today, calendar: calendar)

        let pointToday = LocationPoint(latitude: 37.77, longitude: -122.41, timestamp: today)
        let pointYesterday = LocationPoint(latitude: 37.77, longitude: -122.41, timestamp: calendar.date(byAdding: .day, value: -1, to: today)!)

        XCTAssertTrue(interval.contains(pointToday.timestamp))
        XCTAssertFalse(interval.contains(pointYesterday.timestamp))
    }

    func testNextDayDisabledOnToday() {
        let today = Date()
        XCTAssertTrue(HeatmapGridMath.isToday(today))

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        XCTAssertFalse(HeatmapGridMath.isToday(yesterday))
    }

    func testDensityGridComputation() {
        let coords = [
            (latitude: 37.7749, longitude: -122.4194),
            (latitude: 37.7749, longitude: -122.4194),
            (latitude: 37.7800, longitude: -122.4100)
        ]
        let cells = HeatmapGridMath.computeDensityGrid(coordinates: coords, cellSizeDegrees: 0.001)
        XCTAssertEqual(cells.count, 2)
        let highDensity = cells.first(where: { $0.count == 2 })
        XCTAssertNotNil(highDensity)
        XCTAssertEqual(highDensity?.intensity, 1.0)
    }
}
```

- [ ] **Step 6: Write `README.md`**

Create `README.md`:

```markdown
# Footsteps

A minimal, local-first iOS 17+ application that passively records device location and renders a daily 2D density heatmap.

## Features
- **Local-First & Private**: Zero cloud synchronization, telemetry, or remote servers. All data remains in on-device SwiftData storage.
- **Locked-Device Persistence**: Configured with `FileProtectionType.completeUntilFirstUserAuthentication` to record background location while the device is locked (after initial unlock).
- **Passive Background Tracking**: Standard location updates paired with continuous significant location change monitoring for system relaunch resilience.
- **Daily Heatmap**: Custom MapKit density grid overlay aggregating points per calendar day with DST-aware queries and intuitive day-by-day navigation.

## Architecture & Layout
- `FootstepsApp.swift`: App entry point and `launchOptionsKey.location` background relaunch handling.
- `LocationManager.swift`: `CLLocationManagerDelegate` managing tracking parameters, staged authorization, and storage dispatch.
- `LocationPoint.swift`: SwiftData `@Model` storing `latitude`, `longitude`, `timestamp`, `horizontalAccuracy`.
- `HeatmapMapView.swift`: `UIViewRepresentable` wrapping `MKMapView` and rendering density polygons.
- `DailyTrackerView.swift`: SwiftUI user interface with date browsing and permission recovery banners.
- `HeatmapGridMath.swift`: Foundation math utilities for coordinate validation, DST intervals, and grid aggregation.

## Requirements & Building
- **Environment**: macOS with Xcode 15+ / iOS 17+ SDK.
- **Toolchain**: Swift 6 toolchain configured in Swift 5 language mode (`SWIFT_VERSION = 5.0`).
- **Dependencies**: No third-party packages or CocoaPods required.

To build and run in Xcode:
1. Open `Footsteps.xcodeproj`.
2. Select an iOS 17+ Simulator or connected physical device.
3. Build and Run (`Cmd + R`).

## Verification & Testing
- **Mac CLI Foundation Tests**:
  ```bash
  swiftc Tests/Task1FoundationTests.swift Footsteps/HeatmapGridMath.swift -o /tmp/task1_test && /tmp/task1_test
  swiftc Tests/Task2FoundationTests.swift Footsteps/HeatmapGridMath.swift -o /tmp/task2_test && /tmp/task2_test
  ```
- **Xcode XCTest Suite**: Run unit tests in Xcode (`Cmd + U`).
- **Background Simulation**: Use Simulator menu `Features -> Location -> Freeway Drive` to simulate background updates.
- **Physical Device Verification**: Required to test background relaunch, locked-device write durability, and battery consumption.
```

- [ ] **Step 7: Commit Task 2 files**

```bash
git add Footsteps/HeatmapMapView.swift Footsteps/DailyTrackerView.swift Tests/Task2FoundationTests.swift Tests/UIAndMapTests.swift README.md
git commit -m "feat: implement MapKit heatmap overlay, daily tracker view, and documentation"
```

---

## Verification & Acceptance Checklist

| Requirement | Task / Component | Verification Method |
|---|---|---|
| Four model fields (`latitude`, `longitude`, `timestamp`, `horizontalAccuracy`) | Task 1 (`LocationPoint.swift`) | `LocationAndStorageTests.testLocationPointPersistence` |
| Locked-device write support (`completeUntilFirstUserAuthentication`) | Task 1 (`FootstepsApp.swift`) | `LocationAndStorageTests.testDirectoryFileProtection` |
| Tracking configuration (100m, 50m filter, background mode, significant change) | Task 1 (`LocationManager.swift`) | Source inspection & Simulator execution |
| Background relaunch handling (`UIApplication.LaunchOptionsKey.location`) | Task 1 (`FootstepsApp.swift`) | Source inspection & lifecycle delegate check |
| Invalid coordinate and negative accuracy rejection | Task 1 (`HeatmapGridMath.isValid`) | `Task1FoundationTests` CLI runner |
| DST-aware day intervals `[startOfDay, nextStartOfDay)` | Task 1 (`HeatmapGridMath.dayInterval`) | `Task1FoundationTests` CLI runner |
| Density cell bucketing and intensity normalization | Task 2 (`HeatmapGridMath.computeDensityGrid`) | `Task2FoundationTests` CLI runner |
| Map overlay renderer with intensity alpha | Task 2 (`HeatmapMapView.swift`) | `UIAndMapTests` & UI verification |
| Next day button disabled on current day | Task 2 (`DailyTrackerView.swift`) | `Task1FoundationTests` & `UIAndMapTests` |
| Standalone README and zero 3rd-party dependencies | Task 2 (`README.md`, `project.pbxproj`) | Project build and structure inspection |
