# Pi Working State

## Goal
Implement Footsteps: a local-first, privacy-focused iOS 17+ app that records background location history in SwiftData and displays a daily 2D density heatmap in MapKit.

## Current Task
Task 1 complete (Storage, tracking, app lifecycle, project configuration, and tests). Ready for Task 2.

## Completed
- Approved design spec recorded at `docs/superpowers/specs/2026-09-05-footsteps-design.md`.
- Initialized git repository on branch `feature/footsteps`.
- Authored 2-task implementation plan and task briefs.
- Implemented `Footsteps/HeatmapGridMath.swift`: coordinate validation (finite, in-bounds, non-negative accuracy), DST-aware day interval calculation, and robust density grid bucketing.
- Implemented `Footsteps/LocationPoint.swift`: SwiftData `@Model` with exactly `latitude`, `longitude`, `timestamp`, `horizontalAccuracy`.
- Implemented `Footsteps/LocationManager.swift`: singleton location manager with 100m accuracy, 50m filter, background mode, concurrent significant change monitoring, staged permissions, batch persistence, and accurate error classification.
- Implemented `Footsteps/FootstepsApp.swift`: app entry point with `AppDelegate` location wake relaunch, locked storage file protection (`completeUntilFirstUserAuthentication`), local-only `ModelConfiguration(cloudKitDatabase: .none)`, and visible startup failure handling.
- Configured `Footsteps/Info.plist` with required background mode and location usage descriptions.
- Created `Footsteps.xcodeproj/project.pbxproj` and shared scheme for iOS 17+ / Swift 5.0 mode targeting application and test targets.
- Implemented `Tests/Task1FoundationTests.swift` (standalone CLI runner) and `Tests/LocationAndStorageTests.swift` (iOS XCTest persistence suite).
- Ran CLI Foundation tests and syntax/plist validations.

## Relevant Files
- `Footsteps/HeatmapGridMath.swift`: Foundation math helper for validation and date math.
- `Footsteps/LocationPoint.swift`: SwiftData `@Model`.
- `Footsteps/LocationManager.swift`: Location delegate and background tracking manager.
- `Footsteps/FootstepsApp.swift`: App lifecycle and SwiftData storage configuration.
- `Footsteps/Info.plist`: App property list with background modes and location strings.
- `Footsteps.xcodeproj/project.pbxproj`: Project configuration.
- `Footsteps.xcodeproj/xcshareddata/xcschemes/Footsteps.xcscheme`: Shared Xcode scheme.
- `Tests/Task1FoundationTests.swift`: Pure Foundation test runner.
- `Tests/LocationAndStorageTests.swift`: XCTest persistence and lifecycle tests.

## Architectural Facts & Interface Decisions
- **Stack & Language Mode**: iOS 17+, Swift 5 language mode (`SWIFT_VERSION = 5.0`) on Swift 6 toolchain, zero 3rd-party dependencies.
- **Interim Root View**: `FootstepsApp.swift` presents `InterimRootView` displaying tracking and authorization status. In Task 2, `InterimRootView` is replaced with `DailyTrackerView`.
- **ModelContainer & Locked Persistence**: Directory and database files are set to `FileProtectionType.completeUntilFirstUserAuthentication`. SwiftData configuration sets `cloudKitDatabase: .none`. Startup failure displays a dedicated UI error banner.
- **LocationManager**: Staged permissions flow allows explicit upgrade via `requestPermissions()`. `authorizationStatus` is published on `@MainActor`. Transient location errors (`.locationUnknown`) do not abort tracking.

## Known Failures & Unresolved Risks
- **Hardware Verification Gap**: Physical background wake-up cadence, locked persistence after initial unlock, and relaunch via `launchOptionsKey.location` require testing on a physical iOS device.
- **Environment Toolchain**: Full Xcode iOS SDK and `xcodebuild` are not available in the CLI environment; verification relies on `swiftc` CLI execution, `plutil -lint`, and `swiftc -parse`.

## Next 3 Actions
1. Dispatch worker to execute Task 2 (`.pi/task-2.md`): MapKit heatmap overlay (`HeatmapMapView`), `DailyTrackerView`, UI integration, pure grid tests (`Task2FoundationTests`), `UIAndMapTests`, and `README.md`.
2. Verify Task 2 Foundation tests (`swiftc Tests/Task2FoundationTests.swift Footsteps/HeatmapGridMath.swift -o /tmp/task2_test && /tmp/task2_test`).
3. Perform comprehensive repository review and finalize implementation.
