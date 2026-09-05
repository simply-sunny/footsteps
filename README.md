# Footsteps

A minimal, local-first iOS 17+ app that passively records device location and renders a daily 2D density heatmap.

## Architecture
- **`FootstepsApp.swift`**: App entry point, storage file protection configuration, and background relaunch handling (`UIApplication.LaunchOptionsKey.location`).
- **`LocationManager.swift`**: `@MainActor` singleton managing continuous tracking (100m accuracy, 50m filter), significant location change monitoring, staged permissions, and background persistence.
- **`LocationPoint.swift`**: SwiftData `@Model` storing `latitude`, `longitude`, `timestamp`, and `horizontalAccuracy`.
- **`HeatmapMapView.swift`**: `UIViewRepresentable` wrapping `MKMapView` and rendering density grid overlays with intensity-scaled alpha blending.
- **`DailyTrackerView.swift`**: SwiftUI interface providing day-by-day navigation, predicate-filtered daily queries, and permission/error handling.
- **`HeatmapGridMath.swift`**: Foundation math utilities for coordinate validation, DST-aware calendar day intervals, navigation guards, and density grid bucketing.

## Requirements & Build
- **Target**: iOS 17.0+
- **Language Mode**: Swift 5.0 mode (`SWIFT_VERSION = 5.0`) on Swift 6 toolchain
- **Dependencies**: Zero external dependencies (Apple system frameworks only)

To build and run in Xcode:
1. Open `Footsteps.xcodeproj`.
2. Select the `Footsteps` scheme and an iOS 17+ Simulator or connected iOS device.
3. Build and run (`Cmd + R`).

## Verification & Testing
- **Foundation CLI Tests**:
  ```bash
  swiftc Tests/Task1FoundationTests.swift Footsteps/HeatmapGridMath.swift -o /tmp/task1_test && /tmp/task1_test
  swiftc Tests/Task2FoundationTests.swift Footsteps/HeatmapGridMath.swift -o /tmp/task2_test && /tmp/task2_test
  ```
- **XCTest Suite**: Run unit and integration tests in Xcode (`Cmd + U`).
- **Simulator Testing**: Use Simulator menu `Features -> Location -> Freeway Drive` to simulate live location updates.
- **Physical Device Verification**: Physical hardware is required to validate background wake-up cadence, locked-device writes (`completeUntilFirstUserAuthentication` after initial unlock), relaunch upon termination, and battery efficiency.
