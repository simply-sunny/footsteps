# Footsteps

A minimal, local-first iOS 17+ app that passively records device location and renders a daily 2D density heatmap.

## Architecture
- **`FootstepsApp.swift`**: App entry point, storage file protection configuration (`completeUntilFirstUserAuthentication`), and background relaunch handling (`UIApplication.LaunchOptionsKey.location`).
- **`LocationManager.swift`**: `@MainActor` singleton managing continuous tracking (100m accuracy, 50m distance filter), significant location change monitoring, staged permissions, and background persistence.
- **`LocationPoint.swift`**: SwiftData `@Model` storing `latitude`, `longitude`, `timestamp`, and `horizontalAccuracy`.
- **`HeatmapMapView.swift`**: `UIViewRepresentable` wrapping `MKMapView` and rendering density grid overlays (`HeatmapOverlay` and `HeatmapOverlayRenderer`) with intensity-scaled alpha blending.
- **`DailyTrackerView.swift`**: SwiftUI interface providing day-by-day navigation, predicate-filtered daily queries, and permission/error handling.
- **`HeatmapGridMath.swift`**: Foundation math utilities for coordinate validation, DST-aware calendar day intervals, navigation guards, and density grid bucketing.

## Requirements & Device Setup

### Prerequisites
- **Target**: iOS 17.0+
- **Toolchain**: Xcode 15+ / Swift 5.0 mode (`SWIFT_VERSION = 5.0`) on Swift 6 toolchain
- **Dependencies**: Zero external dependencies (Apple system frameworks only)

### Code Signing & Physical Device Deployment
1. **Open Project**: Open `Footsteps.xcodeproj` in Xcode.
2. **Configure Signing**: Under **Footsteps Target > Signing & Capabilities**:
   - Check **Automatically manage signing**.
   - Select your **Personal Team**.
   - Change the **Bundle Identifier** to a globally unique identifier (e.g. `com.<your-name>.Footsteps`).
3. **Enable Developer Mode**: On iOS 16+, enable Developer Mode on your physical device via **Settings > Privacy & Security > Developer Mode** and restart the device when prompted.
4. **Build & Run**: Connect your device via USB/Wi-Fi, trust the computer if prompted, select your device in the Xcode run destination, and press **Run** (`Cmd + R`).
5. **Provisioning Note**: Free personal Apple Developer accounts generate development provisioning profiles that periodically expire, requiring the app to be re-signed and reinstalled from Xcode. This workflow is intended for personal self-use and testing, not App Store distribution.

## Background Tracking & Lifecycle Behavior

- **Location Authorization Levels**:
  - **Always Authorization**: Enables unattended background relaunches and significant location change wakeups by iOS even if the app process has been terminated by system resource pressure.
  - **WhenInUse Authorization**: An ongoing authorized location session with background location capabilities (`UIBackgroundModes: location`) can continue recording points in the background while the process remains active, but iOS will not automatically relaunch a terminated process without Always authorization.
- **System Constraints & Battery Management**:
  - **User Force-Quit**: If the user explicitly terminates the app from the iOS App Switcher, iOS suspends location delivery and will not wake or relaunch the app. The user must manually reopen the app to resume tracking.
  - **System-Controlled Delivery**: Location event dispatching in the background is governed by iOS power management and hardware heuristics; instantaneous delivery for every single movement is not guaranteed.
  - **System Settings**: Background App Refresh, Low Power Mode, and system-level Location Services settings directly influence background wake cadence.
  - **First Unlock After Reboot**: Storage is protected with `completeUntilFirstUserAuthentication`. Following a device reboot, the user must unlock the device at least once (via passcode or Face ID) before the app can read or write location records during background wakeups.

## Verification & Testing

### CLI Foundation Tests
Run Foundation unit tests on any macOS host with the Swift CLI:
```bash
swiftc Tests/Task1FoundationTests.swift Footsteps/HeatmapGridMath.swift -o /tmp/task1_test && /tmp/task1_test
swiftc Tests/Task2FoundationTests.swift Footsteps/HeatmapGridMath.swift -o /tmp/task2_test && /tmp/task2_test
```

*Note: CLI-only environments without the full Xcode iOS SDK or Simulator cannot execute iOS build/runtime tests (UIKit/SwiftUI/MapKit UI rendering, CoreLocation hardware updates, and SwiftData SQLite integration).*

### Xcode Test Suite & Simulator Testing
- **XCTest Suite**: Run unit and integration tests in Xcode (`Cmd + U`).
- **Simulator Simulation**: Use Simulator menu **Features > Location > Freeway Drive** or **City Run** to simulate active movement and real-time heatmap updates.

### Manual Acceptance Checklist
- [ ] **Permission Denial & Upgrade**: Confirm initial WhenInUse prompt, verify banner / settings navigation when permission is denied, and test upgrading permission to Always in iOS Settings.
- [ ] **Data Persistence & Relaunch**: Record points, terminate the app (or restart in Xcode), relaunch, and confirm all historical points remain persisted in SwiftData storage.
- [ ] **Day Navigation & Empty Days**: Navigate to past days, verify empty days render cleanly without stale overlays or crashes, and confirm next-day navigation is disabled on today/future dates.
- [ ] **Heatmap Overlay Rendering**: Verify density cells scale intensity (alpha blending) correctly as location count increases in a cell.
- [ ] **Locked Walk & Battery Observation**: Perform a physical walk with the device screen locked, confirm continuous background recording across locations, and monitor battery usage over extended tracking sessions.

## License

Licensed under the [MIT License](LICENSE).
