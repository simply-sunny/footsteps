# Pi Working State

## Goal
Implement Footsteps: a local-first, privacy-focused iOS 17+ app that records background location history in SwiftData and displays a daily 2D density heatmap in MapKit.

## Current Task
Implementation planning complete and approved; task briefs ready for worker execution.

## Completed
- Approved design spec recorded at `docs/superpowers/specs/2026-09-05-footsteps-design.md`.
- Initialized git repository on branch `feature/footsteps` with complete `.gitignore`.
- Authored 2-task implementation plan at `docs/superpowers/plans/2026-09-05-footsteps.md` adhering to TDD with pure Foundation CLI checks (`swiftc`) and Xcode XCTest definitions.
- Authored standalone actionable task briefs at `.pi/task-1.md` and `.pi/task-2.md` with exact shared interfaces and constraints.
- Committed approved spec, plan, and task briefs.

## Relevant Files
- `docs/superpowers/specs/2026-09-05-footsteps-design.md`: Approved design specification.
- `docs/superpowers/plans/2026-09-05-footsteps.md`: Detailed implementation plan.
- `.pi/task-1.md`: Brief for Task 1 (Storage, tracking, app lifecycle, project configuration, tests).
- `.pi/task-2.md`: Brief for Task 2 (MapKit grid, daily UI, integration tests, README).
- `.pi/WORKING_STATE.md`: Durable state tracking file.

## Architectural Facts & Interface Decisions
- **Stack & Language Mode**: iOS 17+, Swift 5 language mode (`SWIFT_VERSION = 5.0`) on Swift 6 toolchain, zero 3rd-party dependencies.
- **Pure Logic CLI Verification**: Coordinate validation, DST-aware day interval calculation, and 2D density grid bucketing/intensity calculation are encapsulated in `HeatmapGridMath.swift` (Foundation only), enabling standalone `swiftc` execution on macOS CLI.
- **Core App Files (~5 Files + 1 Helper)**:
  - `FootstepsApp.swift`: App entry point, `AppDelegateAdaptor` handling background relaunch (`UIApplication.LaunchOptionsKey.location`), SwiftData `ModelContainer` directory setup with `FileProtectionType.completeUntilFirstUserAuthentication`.
  - `LocationManager.swift`: Singleton `@MainActor` managing `CLLocationManager`, 100m accuracy, 50m filter, background location updates, significant change monitoring, staged permissions, invalid point filtering.
  - `LocationPoint.swift`: SwiftData `@Model` storing strictly `latitude`, `longitude`, `timestamp`, `horizontalAccuracy`.
  - `HeatmapGridMath.swift`: Foundation helper for coordinate validation, DST day intervals, and density grid calculations.
  - `HeatmapMapView.swift`: `UIViewRepresentable` wrapping `MKMapView` with custom `DensityPolygon` (`MKPolygon`) and intensity-scaled alpha renderer.
  - `DailyTrackerView.swift`: Single-screen SwiftUI view with previous/next day navigation (next disabled on today), date header, point counter, permission warning banner, and `HeatmapMapView`.

## Known Failures & Unresolved Risks
- **Hardware Verification Gap**: Physical background wake-up cadence, locked persistence after initial unlock, and relaunch via `launchOptionsKey.location` require testing on a physical iOS device.

## Next 3 Actions
1. Dispatch worker to execute Task 1 (`.pi/task-1.md`): storage, tracking, lifecycle, project configuration, and tests.
2. Dispatch worker to execute Task 2 (`.pi/task-2.md`): MapKit heatmap overlay, DailyTrackerView, UI integration, pure grid tests, and README.
3. Perform end-to-end verification of pure CLI test runners and inspect repository diffs.
