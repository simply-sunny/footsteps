import XCTest
import SwiftData
import CoreLocation
@testable import Footsteps

final class LocationAndStorageTests: XCTestCase {
    private var tempDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FootstepsTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
    }

    override func tearDownWithError() throws {
        if let url = tempDirectoryURL {
            try? FileManager.default.removeItem(at: url)
        }
        try super.tearDownWithError()
    }

    func testDiskPersistenceAndReadbackAcrossContainers() throws {
        let storeURL = tempDirectoryURL.appendingPathComponent("persistence_test.store")
        let schema = Schema([LocationPoint.self])
        let config = ModelConfiguration("TestStore", schema: schema, url: storeURL, allowsSave: true, cloudKitDatabase: .none)

        let testTimestamp = Date(timeIntervalSince1970: 1700000000)

        // Session 1: Insert and save point to disk store
        do {
            let container1 = try ModelContainer(for: schema, configurations: [config])
            let context1 = ModelContext(container1)
            let point = LocationPoint(
                latitude: 37.7749,
                longitude: -122.4194,
                timestamp: testTimestamp,
                horizontalAccuracy: 12.5
            )
            context1.insert(point)
            try context1.save()
        }

        // Session 2: Relaunch / readback from fresh container instance pointing to same file
        do {
            let container2 = try ModelContainer(for: schema, configurations: [config])
            let context2 = ModelContext(container2)
            let descriptor = FetchDescriptor<LocationPoint>()
            let fetched = try context2.fetch(descriptor)

            XCTAssertEqual(fetched.count, 1, "Should read back exactly 1 persisted point")
            let loaded = try XCTUnwrap(fetched.first)
            XCTAssertEqual(loaded.latitude, 37.7749, accuracy: 0.000001)
            XCTAssertEqual(loaded.longitude, -122.4194, accuracy: 0.000001)
            XCTAssertEqual(loaded.timestamp.timeIntervalSince1970, testTimestamp.timeIntervalSince1970, accuracy: 0.001)
            XCTAssertEqual(loaded.horizontalAccuracy, 12.5, accuracy: 0.001)
        }
    }

    func testDirectoryFileProtection() throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: tempDirectoryURL.path)
        let protection = attributes[FileAttributeKey.protectionKey] as? FileProtectionType
        #if targetEnvironment(simulator)
        // Simulator filesystem (APFS on macOS) does not retain iOS file protection attributes.
        XCTAssertTrue(protection == nil || protection == FileProtectionType.completeUntilFirstUserAuthentication)
        #else
        XCTAssertEqual(protection, FileProtectionType.completeUntilFirstUserAuthentication)
        #endif
    }

    func testCoordinateValidation() {
        XCTAssertTrue(TrajectoryMath.isValid(latitude: 37.7749, longitude: -122.4194, horizontalAccuracy: 5.0))
        XCTAssertTrue(TrajectoryMath.isValid(latitude: -90.0, longitude: -180.0, horizontalAccuracy: 0.0))
        XCTAssertTrue(TrajectoryMath.isValid(latitude: 90.0, longitude: 180.0, horizontalAccuracy: 100.0))
        XCTAssertTrue(TrajectoryMath.isValid(latitude: 37.7749, longitude: -122.4194, horizontalAccuracy: 200.0))

        XCTAssertFalse(TrajectoryMath.isValid(latitude: 90.001, longitude: 0.0, horizontalAccuracy: 5.0))
        XCTAssertFalse(TrajectoryMath.isValid(latitude: -90.001, longitude: 0.0, horizontalAccuracy: 5.0))
        XCTAssertFalse(TrajectoryMath.isValid(latitude: 0.0, longitude: 180.001, horizontalAccuracy: 5.0))
        XCTAssertFalse(TrajectoryMath.isValid(latitude: 0.0, longitude: -180.001, horizontalAccuracy: 5.0))
        XCTAssertFalse(TrajectoryMath.isValid(latitude: 37.77, longitude: -122.41, horizontalAccuracy: -1.0))
        XCTAssertFalse(TrajectoryMath.isValid(latitude: 37.77, longitude: -122.41, horizontalAccuracy: 200.1))

        XCTAssertFalse(TrajectoryMath.isValid(latitude: Double.nan, longitude: 0.0, horizontalAccuracy: 5.0))
        XCTAssertFalse(TrajectoryMath.isValid(latitude: 0.0, longitude: Double.nan, horizontalAccuracy: 5.0))
        XCTAssertFalse(TrajectoryMath.isValid(latitude: 0.0, longitude: 0.0, horizontalAccuracy: Double.nan))
        XCTAssertFalse(TrajectoryMath.isValid(latitude: Double.infinity, longitude: 0.0, horizontalAccuracy: 5.0))
        XCTAssertFalse(TrajectoryMath.isValid(latitude: 0.0, longitude: Double.infinity, horizontalAccuracy: 5.0))
        XCTAssertFalse(TrajectoryMath.isValid(latitude: 0.0, longitude: 0.0, horizontalAccuracy: Double.infinity))
    }

    @MainActor
    func testTrackingDecisionLogic() {
        // Disabled tracking should NEVER start, regardless of auth status or current tracking state
        XCTAssertFalse(LocationManager.shouldStartTracking(isEnabled: false, authorizationStatus: .authorizedAlways, isAlreadyTracking: false))
        XCTAssertFalse(LocationManager.shouldStartTracking(isEnabled: false, authorizationStatus: .authorizedWhenInUse, isAlreadyTracking: false))
        XCTAssertFalse(LocationManager.shouldStartTracking(isEnabled: false, authorizationStatus: .notDetermined, isAlreadyTracking: false))
        XCTAssertFalse(LocationManager.shouldStartTracking(isEnabled: false, authorizationStatus: .denied, isAlreadyTracking: false))
        XCTAssertFalse(LocationManager.shouldStartTracking(isEnabled: false, authorizationStatus: .restricted, isAlreadyTracking: false))

        // Already tracking should not start again (no-op guard)
        XCTAssertFalse(LocationManager.shouldStartTracking(isEnabled: true, authorizationStatus: .authorizedAlways, isAlreadyTracking: true))
        XCTAssertFalse(LocationManager.shouldStartTracking(isEnabled: true, authorizationStatus: .authorizedWhenInUse, isAlreadyTracking: true))

        // Denied or restricted auth should NEVER start
        XCTAssertFalse(LocationManager.shouldStartTracking(isEnabled: true, authorizationStatus: .denied, isAlreadyTracking: false))
        XCTAssertFalse(LocationManager.shouldStartTracking(isEnabled: true, authorizationStatus: .restricted, isAlreadyTracking: false))

        // Enabled and authorized/notDetermined should start when not already tracking
        XCTAssertTrue(LocationManager.shouldStartTracking(isEnabled: true, authorizationStatus: .authorizedAlways, isAlreadyTracking: false))
        XCTAssertTrue(LocationManager.shouldStartTracking(isEnabled: true, authorizationStatus: .authorizedWhenInUse, isAlreadyTracking: false))
        XCTAssertTrue(LocationManager.shouldStartTracking(isEnabled: true, authorizationStatus: .notDetermined, isAlreadyTracking: false))
    }

    @MainActor
    func testPersistedTrackingDisabledFlag() {
        let key = LocationManager.trackingEnabledKey
        let originalValue = UserDefaults.standard.object(forKey: key)

        defer {
            if let orig = originalValue {
                UserDefaults.standard.set(orig, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        // Set tracking disabled
        LocationManager.shared.setTrackingEnabled(false)
        XCTAssertFalse(LocationManager.shared.isTrackingEnabled)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: key))
        XCTAssertFalse(LocationManager.shared.isTrackingActive)

        // Set tracking enabled
        LocationManager.shared.setTrackingEnabled(true)
        XCTAssertTrue(LocationManager.shared.isTrackingEnabled)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key))
    }
}
