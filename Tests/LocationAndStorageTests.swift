import XCTest
import SwiftData
import CoreLocation
import SQLite3
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

    func testActualHistoricalDBCopyMigration() throws {
        var rawSourceURL: URL? = nil

        // 1. Check environment variable if provided
        if let envPath = ProcessInfo.processInfo.environment["FOOTSTEPS_HISTORICAL_STORE_PATH"], !envPath.isEmpty {
            let envURL = URL(fileURLWithPath: envPath)
            if FileManager.default.fileExists(atPath: envURL.path) {
                rawSourceURL = envURL
            }
        }

        // 2. Check app Documents directory (for simulator sandbox container injection)
        if rawSourceURL == nil {
            if let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                for filename in ["historical_raw.store", "default.store"] {
                    let candidateURL = docsURL.appendingPathComponent(filename)
                    if FileManager.default.fileExists(atPath: candidateURL.path) {
                        rawSourceURL = candidateURL
                        break
                    }
                }
            }
        }

        // 3. Check host fixture path if accessible to test process
        if rawSourceURL == nil {
            let tmpURL = URL(fileURLWithPath: "/tmp/footsteps_diag_raw/default.store")
            if FileManager.default.fileExists(atPath: tmpURL.path) {
                rawSourceURL = tmpURL
            }
        }

        guard let sourceURL = rawSourceURL else {
            throw XCTSkip("Historical database copy fixture not available in environment or sandbox Documents")
        }

        // Read source SQLite row values directly prior to migration to verify exact value preservation
        let expectedRows = try readHistoricalV1StoreRows(at: sourceURL)
        XCTAssertEqual(expectedRows.count, 139, "Expected historical extracted database to contain exactly 139 records")

        let storeURL = tempDirectoryURL.appendingPathComponent("actual_copy.store")
        try FileManager.default.copyItem(at: sourceURL, to: storeURL)

        // Also copy wal/shm if present alongside the source file
        let sourceBase = sourceURL.deletingPathExtension()
        let shmSource = sourceBase.appendingPathExtension("store-shm")
        if FileManager.default.fileExists(atPath: shmSource.path) {
            try? FileManager.default.copyItem(at: shmSource, to: tempDirectoryURL.appendingPathComponent("actual_copy.store-shm"))
        }
        let walSource = sourceBase.appendingPathExtension("store-wal")
        if FileManager.default.fileExists(atPath: walSource.path) {
            try? FileManager.default.copyItem(at: walSource, to: tempDirectoryURL.appendingPathComponent("actual_copy.store-wal"))
        }

        let schemaV2 = Schema(versionedSchema: LocationSchemaV2.self)
        let configV2 = ModelConfiguration("ActualCopyStore", schema: schemaV2, url: storeURL, allowsSave: true, cloudKitDatabase: .none)

        let containerV2 = try ModelContainer(
            for: schemaV2,
            migrationPlan: LocationMigrationPlan.self,
            configurations: [configV2]
        )
        let contextV2 = ModelContext(containerV2)
        let descriptor = FetchDescriptor<LocationPoint>(sortBy: [SortDescriptor(\.timestamp, order: .forward)])
        let fetched = try contextV2.fetch(descriptor)

        XCTAssertEqual(fetched.count, expectedRows.count, "All historical records must be preserved across migration without loss")

        for (loaded, expected) in zip(fetched, expectedRows) {
            XCTAssertEqual(loaded.latitude, expected.latitude, accuracy: 0.000001, "Migrated latitude must match source row value exactly")
            XCTAssertEqual(loaded.longitude, expected.longitude, accuracy: 0.000001, "Migrated longitude must match source row value exactly")
            XCTAssertEqual(loaded.timestamp.timeIntervalSinceReferenceDate, expected.timestampReferenceDate, accuracy: 0.001, "Migrated timestamp must match source row value exactly")
            XCTAssertEqual(loaded.horizontalAccuracy, expected.horizontalAccuracy, accuracy: 0.001, "Migrated horizontal accuracy must match source row value exactly")

            // Migrated legacy records must have nil auxiliaries and nil background lifecycle state (unknown)
            XCTAssertNil(loaded.altitude)
            XCTAssertNil(loaded.verticalAccuracy)
            XCTAssertNil(loaded.speed)
            XCTAssertNil(loaded.speedAccuracy)
            XCTAssertNil(loaded.course)
            XCTAssertNil(loaded.courseAccuracy)
            XCTAssertNil(loaded.floor)
            XCTAssertNil(loaded.sourceProvider)
            XCTAssertNil(loaded.isSimulatedBySoftware)
            XCTAssertNil(loaded.isProducedByAccessory)
            XCTAssertNil(loaded.isBackground, "Migrated legacy records must have nil isBackground (unknown lifecycle)")

            // V2 diagnostics defaults
            XCTAssertEqual(loaded.sessionID, "")
            XCTAssertNotNil(loaded.receivedTimestamp)
        }
    }

    private struct HistoricalV1Record {
        let latitude: Double
        let longitude: Double
        let timestampReferenceDate: Double
        let horizontalAccuracy: Double
    }

    private func readHistoricalV1StoreRows(at storeURL: URL) throws -> [HistoricalV1Record] {
        var db: OpaquePointer? = nil
        guard sqlite3_open_v2(storeURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            throw NSError(domain: "SQLiteReadError", code: 1, userInfo: nil)
        }
        defer { sqlite3_close(db) }

        let query = "SELECT ZLATITUDE, ZLONGITUDE, ZTIMESTAMP, ZHORIZONTALACCURACY FROM ZLOCATIONPOINT ORDER BY ZTIMESTAMP ASC;"
        var statement: OpaquePointer? = nil
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw NSError(domain: "SQLiteReadError", code: 2, userInfo: nil)
        }
        defer { sqlite3_finalize(statement) }

        var records: [HistoricalV1Record] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let lat = sqlite3_column_double(statement, 0)
            let lon = sqlite3_column_double(statement, 1)
            let ts = sqlite3_column_double(statement, 2)
            let acc = sqlite3_column_double(statement, 3)
            records.append(HistoricalV1Record(latitude: lat, longitude: lon, timestampReferenceDate: ts, horizontalAccuracy: acc))
        }
        return records
    }

    func testV1toV2SchemaMigrationPreservesExistingRows() throws {
        let storeURL = tempDirectoryURL.appendingPathComponent("migration_test.store")
        let schemaV1 = Schema(versionedSchema: LocationSchemaV1.self)
        let configV1 = ModelConfiguration("MigrationStore", schema: schemaV1, url: storeURL, allowsSave: true, cloudKitDatabase: .none)

        let baseDate = Date(timeIntervalSince1970: 1772900000)
        let sampleCount = 139

        // 1. Create and populate V1 store with 139 synthetic historical records
        do {
            let containerV1 = try ModelContainer(for: schemaV1, configurations: [configV1])
            let contextV1 = ModelContext(containerV1)

            for i in 0..<sampleCount {
                let point = LocationSchemaV1.LocationPoint(
                    latitude: 37.7749 + Double(i) * 0.0001,
                    longitude: -122.4194 + Double(i) * 0.0001,
                    timestamp: baseDate.addingTimeInterval(Double(i * 35)),
                    horizontalAccuracy: 15.5 + Double(i % 10)
                )
                contextV1.insert(point)
            }
            try contextV1.save()
        }

        // 2. Open store with V2 Schema and LocationMigrationPlan
        let schemaV2 = Schema(versionedSchema: LocationSchemaV2.self)
        let configV2 = ModelConfiguration("MigrationStore", schema: schemaV2, url: storeURL, allowsSave: true, cloudKitDatabase: .none)

        let containerV2 = try ModelContainer(
            for: schemaV2,
            migrationPlan: LocationMigrationPlan.self,
            configurations: [configV2]
        )
        let contextV2 = ModelContext(containerV2)
        let descriptor = FetchDescriptor<LocationPoint>(sortBy: [SortDescriptor(\.timestamp, order: .forward)])
        let fetched = try contextV2.fetch(descriptor)

        XCTAssertEqual(fetched.count, sampleCount, "All \(sampleCount) records must be preserved across migration")

        for (i, loaded) in fetched.enumerated() {
            let expectedLat = 37.7749 + Double(i) * 0.0001
            let expectedLon = -122.4194 + Double(i) * 0.0001
            let expectedTime = baseDate.addingTimeInterval(Double(i * 35))
            let expectedAcc = 15.5 + Double(i % 10)

            XCTAssertEqual(loaded.latitude, expectedLat, accuracy: 0.000001)
            XCTAssertEqual(loaded.longitude, expectedLon, accuracy: 0.000001)
            XCTAssertEqual(loaded.timestamp.timeIntervalSince1970, expectedTime.timeIntervalSince1970, accuracy: 0.001)
            XCTAssertEqual(loaded.horizontalAccuracy, expectedAcc, accuracy: 0.001)

            // V2 optional fields must be nil
            XCTAssertNil(loaded.altitude)
            XCTAssertNil(loaded.verticalAccuracy)
            XCTAssertNil(loaded.speed)
            XCTAssertNil(loaded.speedAccuracy)
            XCTAssertNil(loaded.course)
            XCTAssertNil(loaded.courseAccuracy)
            XCTAssertNil(loaded.floor)
            XCTAssertNil(loaded.sourceProvider)
            XCTAssertNil(loaded.isSimulatedBySoftware)
            XCTAssertNil(loaded.isProducedByAccessory)
            XCTAssertNil(loaded.isBackground, "Migrated legacy records must have nil isBackground (unknown lifecycle)")

            // V2 diagnostics defaults
            XCTAssertEqual(loaded.sessionID, "")
            XCTAssertNotNil(loaded.receivedTimestamp)
        }
    }

    func testV1toV2SchemaMigrationStressBenchmark() throws {
        let storeURL = tempDirectoryURL.appendingPathComponent("migration_stress_test.store")
        let schemaV1 = Schema(versionedSchema: LocationSchemaV1.self)
        let configV1 = ModelConfiguration("MigrationStressStore", schema: schemaV1, url: storeURL, allowsSave: true, cloudKitDatabase: .none)

        let baseDate = Date(timeIntervalSince1970: 1772900000)
        let sampleCount = 5000

        // 1. Create and populate V1 store with 5,000 synthetic historical records
        do {
            let containerV1 = try ModelContainer(for: schemaV1, configurations: [configV1])
            let contextV1 = ModelContext(containerV1)

            for i in 0..<sampleCount {
                let point = LocationSchemaV1.LocationPoint(
                    latitude: 37.7749 + Double(i) * 0.00001,
                    longitude: -122.4194 + Double(i) * 0.00001,
                    timestamp: baseDate.addingTimeInterval(Double(i * 10)),
                    horizontalAccuracy: 5.0 + Double(i % 50)
                )
                contextV1.insert(point)
            }
            try contextV1.save()
        }

        // 2. Open store with V2 Schema and LocationMigrationPlan
        let schemaV2 = Schema(versionedSchema: LocationSchemaV2.self)
        let configV2 = ModelConfiguration("MigrationStressStore", schema: schemaV2, url: storeURL, allowsSave: true, cloudKitDatabase: .none)

        let containerV2 = try ModelContainer(
            for: schemaV2,
            migrationPlan: LocationMigrationPlan.self,
            configurations: [configV2]
        )
        let contextV2 = ModelContext(containerV2)
        let descriptor = FetchDescriptor<LocationPoint>()
        let count = try contextV2.fetchCount(descriptor)

        XCTAssertEqual(count, sampleCount, "All \(sampleCount) records must be migrated without loss or SQLite lock timeouts")
    }

    @MainActor
    func testLocationManagerConfiguration() {
        let manager = LocationManager()
        manager.startTracking()

        XCTAssertEqual(manager.coreLocationManager.desiredAccuracy, kCLLocationAccuracyBestForNavigation)
        XCTAssertEqual(manager.coreLocationManager.distanceFilter, kCLDistanceFilterNone)
        XCTAssertEqual(manager.coreLocationManager.activityType, .fitness)
        XCTAssertFalse(manager.coreLocationManager.pausesLocationUpdatesAutomatically)
        XCTAssertTrue(manager.coreLocationManager.showsBackgroundLocationIndicator)
        XCTAssertTrue(manager.coreLocationManager.allowsBackgroundLocationUpdates)
    }

    @MainActor
    func testRawIngestionSavesAllFixes() async throws {
        let schema = Schema(versionedSchema: LocationSchemaV2.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let manager = LocationManager()
        manager.configure(modelContainer: container)

        // Create locations including coarse fixes (> 200m) that legacy ingestion dropped
        let now = Date()
        let coarseFix1 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            altitude: 10.0,
            horizontalAccuracy: 350.0,
            verticalAccuracy: 5.0,
            timestamp: now
        )
        let coarseFix2 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7750, longitude: -122.4195),
            altitude: 12.0,
            horizontalAccuracy: 1200.0,
            verticalAccuracy: 10.0,
            timestamp: now.addingTimeInterval(10)
        )

        manager.locationManager(manager.coreLocationManager, didUpdateLocations: [coarseFix1, coarseFix2])

        try await Task.sleep(nanoseconds: 100_000_000)

        let context = ModelContext(container)
        let fetched = try context.fetch(FetchDescriptor<LocationPoint>())
        XCTAssertEqual(fetched.count, 2, "Raw ingestion must preserve all fixes without dropping coarse accuracy")
    }

    @MainActor
    func testMetadataStampingAndSentinelPreservation() async throws {
        let schema = Schema(versionedSchema: LocationSchemaV2.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let manager = LocationManager()
        manager.configure(modelContainer: container)

        let fixDate = Date(timeIntervalSince1970: 1772900000)
        // Fix reporting valid speed and invalid course/verticalAccuracy sentinels (-1)
        let testLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            altitude: 45.5,
            horizontalAccuracy: 8.2,
            verticalAccuracy: -1.0,
            course: -1.0,
            speed: 1.4,
            timestamp: fixDate
        )

        let beforeTime = Date()
        manager.locationManager(manager.coreLocationManager, didUpdateLocations: [testLocation])
        try await Task.sleep(nanoseconds: 100_000_000)
        let afterTime = Date()

        let context = ModelContext(container)
        let fetched = try context.fetch(FetchDescriptor<LocationPoint>())
        XCTAssertEqual(fetched.count, 1)

        let saved = try XCTUnwrap(fetched.first)
        XCTAssertEqual(saved.latitude, 37.7749, accuracy: 0.0001)
        XCTAssertEqual(saved.longitude, -122.4194, accuracy: 0.0001)
        XCTAssertEqual(saved.timestamp.timeIntervalSince1970, fixDate.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(saved.horizontalAccuracy, 8.2, accuracy: 0.01)

        XCTAssertEqual(saved.altitude ?? 0, 45.5, accuracy: 0.01)
        XCTAssertEqual(saved.verticalAccuracy ?? 0, -1.0, accuracy: 0.01, "Negative sentinel must be preserved as reported")
        XCTAssertEqual(saved.course ?? 0, -1.0, accuracy: 0.01, "Negative sentinel must be preserved as reported")
        XCTAssertEqual(saved.speed ?? 0, 1.4, accuracy: 0.01)
        XCTAssertEqual(saved.sourceProvider, "CoreLocation")
        XCTAssertEqual(saved.sessionID, manager.sessionID)
        XCTAssertFalse(saved.sessionID.isEmpty)
        XCTAssertGreaterThanOrEqual(saved.receivedTimestamp, beforeTime.addingTimeInterval(-1))
        XCTAssertLessThanOrEqual(saved.receivedTimestamp, afterTime.addingTimeInterval(1))
    }

    @MainActor
    func testTransientLocationUnknownDiagnostics() {
        let manager = LocationManager()
        XCTAssertEqual(manager.locationUnknownCount, 0)
        XCTAssertNil(manager.lastLocationUnknownDate)

        let unknownError = CLError(.locationUnknown)
        manager.locationManager(manager.coreLocationManager, didFailWithError: unknownError)

        // Wait for MainActor task
        let expectation = expectation(description: "LocationUnknown handled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            XCTAssertEqual(manager.locationUnknownCount, 1)
            XCTAssertNotNil(manager.lastLocationUnknownDate)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    @MainActor
    func testAuthorizationRefresh() {
        let manager = LocationManager()
        manager.refreshAuthorizationStatus()
        XCTAssertEqual(manager.authorizationStatus, manager.coreLocationManager.authorizationStatus)
    }
}
