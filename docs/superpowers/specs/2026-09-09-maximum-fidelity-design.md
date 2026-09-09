# Footsteps Maximum-Fidelity Architecture & Design Specification

## 1. Overview & Goals
Footsteps is a local-first, privacy-respecting iOS location diary. This maximum-fidelity specification evolves the recording engine and data pipeline from a lossy, filtered collector into an uncompromising raw evidence recorder coupled with an uncertainty-aware reconstruction engine.

- **Primary Mandate**: Record every raw location sample delivered by the OS without pre-storage filtering, capturing rich sensor, source information, and lifecycle metadata while preserving native sentinel values.
- **Reconstruction Principle**: Separate raw evidence from derived display trajectories. Break unknown gaps and non-physical observations rather than bridging them. Group stationary jitter into uncertainty-anchored dwell observations with supported continuous duration. Preserve isolated observations (singletons) as valid historical evidence.
- **Platform**: iOS 17+, Swift 6. Standard Apple frameworks: SwiftUI, SwiftData, Core Location, MapKit.
- **Bundle Identifiers**: Preserve existing targets and bundle identities (`sunny.footsteps.app` for Debug, `sunnny.footsteps.app` for Release). Never alter Release identity or reset user storage.

---

## 2. Baseline Diagnosis & Sanitized Audit Corrections

### 2.1 Empirical Baseline from Historical Store
Inspection of the historical database (`default.store`, 139 records across 5 calendar days) reveals the real-world operating characteristics under the initial V1 configuration:
- **Sample Count**: 139 points across 5 calendar days.
- **Time Intervals ($\Delta t$)**:
  - Mean: 2,546.97 seconds (~42.4 minutes)
  - Median: 33.41 seconds
  - Maximum: 76,430.78 seconds (~21.2 hours)
  - Discontinuities ($\Delta t > 30\text{s}$): 44 occurrences
- **Horizontal Accuracy**:
  - Median: 15.56 meters
  - Maximum: 78.70 meters
  - Discarded on Ingestion ($> 200\text{m}$): 0 persisted in legacy store (filter was active).

### 2.2 Conservative Continuity Policy & Gap Semantics
1. **Conservative Continuity Policy**: Rather than permitting large 5-minute unobserved blind gaps that invent straight-line chords across 1–4.9 minute intervals, the trajectory engine enforces a conservative provisional continuity ceiling of $\le 30\text{s}$ by default. Grounded in the legacy dataset median (~33.4s) and burst cadence under pedestrian tracking:
   - Smooth 1Hz walking remains continuous.
   - Gaps exceeding 30s (e.g. 40s, 120s, 299s) are split into separate uncertain observations (singletons, dwells, or distinct segments).
   - This threshold is a conservative display continuity policy, not a location guarantee; unavoidable discrete interpolation remains between consecutive fixes within the sampling window. Physical outdoor baseline and battery consumption remain pending on-device validation.
2. **Raw Sentinel Preservation**: CoreLocation reports negative values (e.g. `-1` speed, course, vertical accuracy) when measurements are invalid. Ingestion preserves these raw values rather than converting them to `nil`.
3. **Source Information**: iOS 15+ `CLLocation.sourceInformation` flags (`isSimulatedBySoftware`, `isProducedByAccessory`) are captured as optional booleans.
4. **Lifecycle Categorization**: Stamped `isBackground` is an optional boolean (`true` for background, `false` for foreground, `nil` for legacy/unknown migrated data).
5. **Transient Errors**: `CLError.locationUnknown` events are diagnosed as transient GNSS search events and counted in telemetry rather than attributed to app lifecycle crashes.

---

## 3. Location Collection Engine (`LocationManager`)

### 3.1 CoreLocation Configuration
- **Manager**: Single continuous `CLLocationManager` instance.
- **Accuracy**: `desiredAccuracy = kCLLocationAccuracyBestForNavigation`.
- **Distance Filter**: `distanceFilter = kCLDistanceFilterNone` (zero filtering; captures every fix including subtle movement and stationary jitter).
- **Activity Type**: `activityType = .fitness` (tunes Kalman filters and GNSS duty cycles for pedestrian kinematics).
- **Background Mode**:
  - `allowsBackgroundLocationUpdates = true` (`UIBackgroundModes: location`)
  - `showsBackgroundLocationIndicator = true` (promotes continuous background location without OS-forced suspension).
  - `pausesLocationUpdatesAutomatically = false` (prevents system auto-pausing).
- **Recovery Registrations**: `startMonitoringSignificantLocationChanges()` active as a failsafe OS wakeup mechanism.

### 3.2 Authorization & Accuracy Elevation
- Staged permission requests: `requestWhenInUseAuthorization()` -> `requestAlwaysAuthorization()`.
- Precision check: If `accuracyAuthorization == .reducedAccuracy`, provides explicit recovery UI and requests temporary full accuracy via `requestTemporaryFullAccuracyAuthorization(withPurposeKey: "FullAccuracy")`.
- Refresh: Authorization and precision status are refreshed whenever the app returns to foreground.

### 3.3 Raw Ingestion Pipeline
- **Zero Loss Rule**: Ingestion saves all delivered fixes directly into SwiftData without filtering.
- **Sentinel Preservation**: Raw `altitude`, `verticalAccuracy`, `speed`, `speedAccuracy`, `course`, and `courseAccuracy` are stored directly as reported.
- **Session Attribution**: Distinct `sessionID` generated per launch/wake.
- **State Attribution**: Ingestion stamps `receivedTimestamp = Date()` and records `isBackground` via `UIApplication.shared.applicationState != .active`.

---

## 4. SwiftData Persistence & Safe Schema Migration

### 4.1 Schema Evolution (`SchemaV1` $\rightarrow$ `SchemaV2`)

#### `LocationSchemaV1` (Legacy)
```swift
@Model
final class LocationPoint {
    var latitude: Double
    var longitude: Double
    var timestamp: Date
    var horizontalAccuracy: Double
}
```

#### `LocationSchemaV2` (Maximum Fidelity)
```swift
@Model
final class LocationPoint {
    var latitude: Double
    var longitude: Double
    var timestamp: Date
    var horizontalAccuracy: Double

    // Auxiliary CoreLocation metrics (preserving raw reported values)
    var altitude: Double?
    var verticalAccuracy: Double?
    var speed: Double?
    var speedAccuracy: Double?
    var course: Double?
    var courseAccuracy: Double?
    var floor: Int?
    var sourceProvider: String?

    // iOS 15+ CoreLocation source information
    var isSimulatedBySoftware: Bool?
    var isProducedByAccessory: Bool?

    // Ingestion & Lifecycle diagnostics
    var receivedTimestamp: Date = Date()
    var sessionID: String = ""
    var isBackground: Bool? = nil
}
```

### 4.2 Migration Plan
- `SchemaMigrationPlan` with `MigrationStage.lightweight(fromVersion: LocationSchemaV1.self, toVersion: LocationSchemaV2.self)`.
- Verified against historical database copy (via optional `FOOTSTEPS_HISTORICAL_STORE_PATH` fixture or sandbox documents) and 5,000-record synthetic benchmark stress tests.
- File protection: `completeUntilFirstUserAuthentication`.

---

## 5. Derived Segmentation & Trajectory Processing

### 5.1 Anchored Stationary Grouping & Trajectory Processing
Reconstruction occurs at query time via `TrajectoryMath.analyzeDay`:
1. **Raw Query**: Retrieve all points within calendar day interval `[startOfDay, nextStartOfDay)`.
2. **Timeline Gap Audit**: Consecutive raw points with $\Delta t > 30\text{s}$ are detected across the observation timeline and recorded in `gapCount` and `maxGapSeconds`.
3. **Classification**:
   - `Usable`: $0 \le \text{horizontalAccuracy} \le 100\text{m}$.
   - `Suspicious`: $100\text{m} < \text{horizontalAccuracy} \le 200\text{m}$.
   - `Outlier / Barrier`: $\text{horizontalAccuracy} > 200\text{m}$ or non-finite/out-of-bounds (flushes active run; never bridged).
4. **Display De-duplication**: Exact duplicate timestamps ($\Delta t == 0$) are de-duplicated for display by retaining the fix with the highest precision without breaking continuous paths.
5. **Anchored Stationary Evaluation**:
   - Contiguous runs evaluate total displacement relative to anchor uncertainty: $\text{maxDisplacement} \le \max(\text{acc}_{\text{anchor}}, 10\text{m})$.
   - If displacement stays within uncertainty: grouped as `TrajectorySingleton` with supported `observationDuration` (equal to continuous non-gap span).
   - If cumulative displacement exceeds uncertainty (slow cumulative walking): preserved as a full multi-point `TrajectorySegment`.
   - Discontinuity breaks ($\Delta t > 30\text{s}$, $\Delta d > 10\text{km}$, $\text{speed} > 50\text{m/s}$) flush active runs immediately.

---

## 6. User Interface & Diagnostics

### 6.1 Map View (`TrajectoryMapView`)
- **Map Controls**: Native `MKCompassButton` and `MKUserTrackingButton` positioned at bottom corners (above safe area).
- **Viewport Stability**: Bounding rect framing occurs only on date change or initial load; live updates preserve user pan and zoom.
- **Diagnostics Overlay**: Toggleable debug overlay rendering per-point uncertainty halos, classification colors (usable, suspicious, outlier), time deltas, and segment boundaries.

### 6.2 Date Navigation & Quiet UI
- Date navigation bar with previous/next chevrons, DatePicker, and Settings gear.
- Exact empty state overlay: `"No data for this day."`.

### 6.3 Dedicated Settings & Diagnostic Sheet
- **Tracking & Permissions**: Background tracking toggle, authorization status, precise location indicator, and recovery button.
- **Diagnostics Map Toggle**: Enable/disable raw point and accuracy circle visualization.
- **Telemetry Section**: Raw points, usable/suspicious/outliers, segments, singletons/dwells, gaps (>30s), max gap, median/worst accuracy, lifecycle breakdown (`bg`/`fg`/`unk`), and transient `locationUnknown` counters.

---

## 7. Verification Strategy & Test Matrix
- **43 automated unit & integration tests** in `FootstepsTests` on iOS Simulator (13 `LocationAndStorageTests`, 30 `UIAndMapTests`).
- **2 standalone mathematical suites** (`Task1FoundationTests`, `Task2FoundationTests`).
- **Historical database migration test** verifying non-destructive schema migration.
- **Physical release upgrade verification** confirming 141 legacy records preserved intact and active/non-active ingestion verified.
- **Dual build verification**: Debug (`sunny.footsteps.app`) and Release (`sunnny.footsteps.app`).
