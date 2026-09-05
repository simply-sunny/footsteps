# Footsteps V1 Design Specification

## 1. Overview & Scope
Footsteps is a minimal, local-first iOS 17+ application that passively records device location and renders a daily density-grid heatmap.

- **Platform**: iOS 17+, Swift 6.
- **Frameworks**: SwiftUI, SwiftData, Core Location, MapKit (`MKMapView`).
- **Target File Count**: ~5 Swift files.
- **Explicit Non-Goals**: No user accounts, remote backend, iCloud synchronization, analytics/telemetry, settings screens, third-party dependencies, or CI pipelines.

---

## 2. Architecture & File Layout (~5 Files)
1. **`FootstepsApp.swift`**: Application entry point and lifecycle delegate for background relaunch handling (`UIApplication.LaunchOptionsKey.location`).
2. **`LocationManager.swift`**: `CLLocationManagerDelegate` wrapper managing standard updates, significant change monitoring, and staged permissions.
3. **`LocationPoint.swift`**: SwiftData `@Model` storing four attributes: `latitude: Double`, `longitude: Double`, `timestamp: Date`, `horizontalAccuracy: Double`.
4. **`HeatmapMapView.swift`**: `UIViewRepresentable` wrapping `MKMapView` with a custom `MKOverlay` / `MKOverlayRenderer` generating a daily 2D density grid.
5. **`DailyTrackerView.swift`**: Main single-screen interface showing the map, current date banner, and previous/next day buttons (next disabled when viewing today).

---

## 3. Location Tracking & Lifecycle
- **Initialization**: Instantiated at app launch level (AppDelegate / App init), independent of view appearance, ensuring capture during background wakes.
- **Tracking Profile**:
  - `desiredAccuracy = kCLLocationAccuracyHundredMeters`
  - `distanceFilter = 50.0` meters
  - `activityType = .other`
  - `allowsBackgroundLocationUpdates = true` (`UIBackgroundModes: location`)
  - `pausesLocationUpdatesAutomatically = false` (no auto-pause without proven recovery).
- **Wakeup & Recovery**: Significant-change monitoring (`startMonitoringSignificantLocationChanges()`) runs concurrently to enable OS relaunch if the background process is terminated.
- **Constraints & Edge Cases**:
  - Significant-change dispatch intervals are system-managed without fixed delivery guarantees.
  - User force-quit interrupts tracking; the user should reopen the app to resume. Do not promise automatic recovery from force-quit.
  - No speculative active/stationary state machines; both monitors remain registered.
- **Permissions Flow**: Staged progression (When In Use requested first, followed by Always with minimal explanatory context). Denied states present a clear recovery path linking to iOS Settings.

---

## 4. SwiftData Persistence & Locked Storage
- **Store Configuration**: Single local-only `ModelContainer`. Storage directory is explicitly verified/configured with `FileProtectionType.completeUntilFirstUserAuthentication` to permit background writes while the device is locked (after first unlock).
- **Integrity & Errors**: Save errors are propagated and visible in runtime logging/UI alerts. Corrupt stores are never silently deleted, and in-memory fallbacks are disallowed.
- **Queries**: Fetches use DST-aware date interval predicates: `[calendar.startOfDay(for: date), calendar.date(byAdding: .day, value: 1, to: startOfDay)!)`. No unbounded or all-history fetches.

---

## 5. Map & Heatmap Visualization
- **Rendering**: `MKMapView` via `UIViewRepresentable` rendering custom density cells bounded to the selected day's points.
- **Performance**: Overlay computation is isolated to daily data mutations to avoid rebuilds on unrelated SwiftUI view redraws.
- **Navigation**: Day browsing (Previous / Next) with next-day navigation disabled on the current calendar day.

---

## 6. Verification Strategy & Acceptance Criteria

### Verification Tiers
1. **Local CLI (Current Environment - macOS Swift 6.4 CLI)**:
   - Pure-logic compilation and unit tests (date math, grid bucketing), plus available syntax/configuration checks. iOS framework type checking and clean builds require full Xcode and the iOS SDK, currently unavailable.
2. **iOS Simulator**:
   - UI navigation (date flipping, disabled next button on today).
   - Permission request prompts and denied state UI.
   - Core Location simulation playback and SwiftData store insertion.
3. **Physical Device (Required for Tracking & Battery)**:
   - Background location acquisition and wake-up.
   - Location recording while locked (post-first-unlock).
   - Background relaunch via `launchOptionsKey.location`.
   - Real-world battery consumption profiling.
   - *Status*: **Physical-device unverified** (pending hardware testing).

### V1 Acceptance Criteria
- [ ] Stored record contains strictly `latitude`, `longitude`, `timestamp`, `horizontalAccuracy`.
- [ ] Background location records successfully while screen is locked (after first unlock).
- [ ] Significant change monitor stays registered alongside standard updates.
- [ ] Map displays density overlay for the selected day; Next button is disabled on today.
- [ ] Queries fetch solely the selected calendar-day interval `[startOfDay, nextStartOfDay)` (not necessarily 24 hours across DST).
- [ ] Save failures surface visibly without silent fallback to in-memory store.
- [ ] Fresh launch opens today; previous/next navigation updates the heatmap correctly.
- [ ] Records survive app termination and relaunch.
- [ ] Both location usage descriptions and the background-location capability are configured.
- [ ] Invalid coordinates and negative accuracy readings are rejected before persistence.

---

## 7. Official References
- Apple Core Location: `developer.apple.com/documentation/corelocation/cllocationmanager`
- Background Location Updates: `developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates`
- Pauses Location Updates Automatically: `developer.apple.com/documentation/corelocation/cllocationmanager/pauseslocationupdatesautomatically`
- Significant Location Changes: `developer.apple.com/documentation/corelocation/cllocationmanager/startmonitoringsignificantlocationchanges()`
- Always Authorization: `developer.apple.com/documentation/corelocation/cllocationmanager/requestalwaysauthorization()`
- Launch Options Location Key: `developer.apple.com/documentation/uikit/uiapplication/launchoptionskey/location`
- File Protection: `developer.apple.com/documentation/foundation/fileprotectiontype/completeuntilfirstuserauthentication`
