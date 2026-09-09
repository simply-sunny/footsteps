<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Footsteps/Assets.xcassets/AppIcon.appiconset/AppIcon-Dark.png">
    <img src="Footsteps/Assets.xcassets/AppIcon.appiconset/AppIcon-Default.png" width="128" height="128" alt="Footsteps logo" />
  </picture>
</p>

# Footsteps

A minimal, local-first iOS 17+ app that passively records device location with maximum fidelity and renders real daily trajectory segments.

## Features

- **Maximum-Fidelity Passive Tracking**: Zero-loss raw evidence ingestion configured with `kCLLocationAccuracyBestForNavigation`, zero distance filter, fitness activity type, background indicator, and temporary full accuracy request.
- **Strict Evidence vs. Inference Storage**: Persistent raw location point history stored locally on-device using versioned SwiftData schemas (`LocationSchemaV1`, `LocationSchemaV2`, `LocationMigrationPlan`) with encrypted file protection (`completeUntilFirstUserAuthentication`).
- **Raw Sentinel & Metadata Preservation**: Captures raw altitude, speed, course, vertical/speed/course accuracies (preserving native negative sentinels such as `-1` without silent nil conversion), floor level, CoreLocation `sourceInformation` flags (`isSimulatedBySoftware`, `isProducedByAccessory`), tracking session ID, lifecycle state (foreground/background/unknown), and reception timestamps without discarding coarse fixes at ingestion.
- **Anchored Uncertainty-Aware Segmentation**: Dynamic trajectory reconstruction with anchored stationary grouping (grouping jitter within uncertainty radius into dwell observations with supported continuous duration), slow cumulative walk preservation, display-only timestamp de-duplication, poor-fix barrier splitting (>200m), speed jump splitting (>50m/s), and chronological sorting.
- **Singleton & Dwell Uncertainty Visualization**: Singletons and stationary dwells rendered as distinct MapKit coordinate overlays with uncertainty halo circles proportional to horizontal accuracy, supported observation duration display, and tap-to-inspect detail cards.
- **Stable Map Viewport & Native Controls**: Date-keyed viewport framing preserves user pan/zoom across live incremental point arrivals. Native `MKCompassButton` and `MKUserTrackingButton` anchored cleanly at bottom edges.
- **Diagnostics Map Overlay & Telemetry**: Debug toggle rendering per-point accuracy halos, classification badges (usable $\le 100\text{m}$, suspicious $100–200\text{m}$, outlier $>200\text{m}$), time deltas, speed, and transient `CLError.locationUnknown` evidence counters.
- **On-Demand HealthKit Steps**: Tapping a trajectory segment presents a compact bottom sheet displaying localized start–end times, duration in minutes, and cumulative HealthKit step counts for the exact segment interval.
- **Privacy-Preserving Degradation**: Gracefully degrades to "Steps unavailable" when steps are denied, unavailable, or on unsupported devices without distinguishing read denial.
- **Date-First Navigation & Precise Location Recovery**: Daily tracker UI with date stepping, calendar day boundary calculations, instant container transitions, precise authorization status display, and on-demand full accuracy recovery actions.
- **Zero Third-Party Dependencies**: Pure Apple system frameworks (`SwiftUI`, `SwiftData`, `MapKit`, `CoreLocation`, `HealthKit`, `UIKit`).
- **Native iOS 18 Dark Appearance Icon**: Configured asset catalog supporting both default and native iOS 18 dark appearance icon styles.

## Requirements

- iOS 17.0+
- Xcode 15+ / Xcode 16+ / Xcode 27 beta (Swift 5.0 mode on Swift 6 toolchain)
- Physical iPhone with Developer Mode enabled (for unattended on-device tracking)
- Apple Developer account (free personal team or paid developer membership)

## Install

1. Clone the repository to your local machine.
2. Open `Footsteps.xcodeproj` in Xcode.
3. Under **Footsteps Target > Signing & Capabilities**, select your **Personal Team** and ensure automatic signing is enabled.
4. Set a unique **Bundle Identifier** (e.g. `com.<your-name>.Footsteps`).
5. On your physical iPhone, enable Developer Mode via **Settings > Privacy & Security > Developer Mode** and reboot when prompted.
6. Connect your iPhone via USB/Wi-Fi, select it as the run destination, and press **Run** (`Cmd + R`).

## Controls

- **Day Navigation**: Tap `<` or `>` in the navigation bar or use the interactive DatePicker to navigate between calendar days (future day navigation is disabled).
- **Segment Inspection**: Tap any trajectory line on the map to select it and view a bottom sheet with start–end time, duration, and on-demand HealthKit step count.
- **Singleton & Dwell Inspection**: Tap isolated points or dwell clusters on the map to view coordinate details, observation duration, and horizontal accuracy circles.
- **Diagnostics Map View**: Enable "Show Diagnostics Map Overlay" in Settings to inspect every raw point, accuracy radius, time delta, and status classification.
- **Diagnostics & Settings**: Tap the gear icon in the navigation bar to open the live telemetry diagnostics sheet.
- **Date Status**: Header displays date selection, error notices, and permission/precision recovery banners.
- **Trajectory View**: Pan and pinch to zoom over the MapKit canvas; tap individual trajectory segments, singletons, or raw points to highlight them.
- **User Tracking**: Tap the native tracking button to toggle location tracking modes.
- **Location Permission Banner**: Tap the warning banner if location permissions or precision are restricted to open iOS Settings or request full accuracy.

## Verification & Testing

The test suite includes 43 automated unit and integration tests (13 Location & Storage tests, 30 UI & Map tests) and 2 standalone mathematical suites:

```bash
# Run Foundation math, segmentation, and navigation test suites via CLI
swiftc Tests/Task1FoundationTests.swift Footsteps/TrajectoryMath.swift -o /tmp/task1_test && /tmp/task1_test
swiftc Tests/Task2FoundationTests.swift Footsteps/TrajectoryMath.swift Footsteps/StepCountReader.swift -o /tmp/task2_test && /tmp/task2_test
```

Full app compilation and UI/MapKit test execution require Xcode with the iOS 17+ SDK:
- **Schema Migration & Data Preservation**: Verified lightweight migration from V1 to V2 across historical database copies and 5,000-record synthetic benchmark stress tests.
- **Physical Upgrade Ingestion**: Verified signed Release build installation over prior versions, confirming 141 historical records preserved with full database integrity and post-launch point ingestion across active and non-active application lifecycle states.
- **Ingestion & Sentinel Preservation**: Verified zero-loss storage, negative sentinel preservation (`-1` speed/course/verticalAccuracy), `sourceInformation` software/accessory flags, session ID tagging, and lifecycle state stamping (`bg`/`fg`/`unk`).
- **Stationary Grouping & Segmentation**: Verified anchored stationary dwell grouping with continuous observation duration, slow cumulative walk preservation, duplicate timestamp display de-duplication, barrier splitting at >200m, speed jump handling at >50m/s, and singleton isolation.
- **UI, Precision & Viewport**: Verified precise authorization recovery, diagnostics overlay rendering, stable map framing across live updates, and instant date transitions.

## Limitations

- **Source-Only Release**: Provided as an uncompiled source project intended for personal self-signed deployment; no prebuilt binaries or App Store distribution.
- **Conservative Continuity Policy**: Trajectory reconstruction uses an explicit provisional continuity ceiling ($\le 30\text{s}$) by default. High-rate walking (~1Hz) remains continuous, while blind gaps $> 30\text{s}$ are preserved as separate uncertain observations (singletons, dwells, or split segments) rather than fabricating speculative straight-line chords across unobserved space.
- **Unavoidable Between-Fix Interpolation**: The $\le 30\text{s}$ continuity threshold is a display and reconstruction heuristic rather than a continuous location ground truth. Straight-line visual connection between consecutive fixes within the sampling window remains an unavoidable discrete interpolation.
- **Stationary Dwell Heuristics**: Dwell grouping applies provisional spatial uncertainty clustering and temporal thresholds; supported observation duration reflects the span of contiguous non-gap fixes within the uncertainty radius rather than a dedicated stationary sensor guarantee.
- **Lifecycle & Background Classification**: Lifecycle telemetry (`isBackground`) records `UIApplication.shared.applicationState != .active` at the moment a fix is received. Non-active reception confirms ingestion during non-foreground execution phases, but should not be equated with guaranteed unthrottled or prolonged locked-screen tracking under iOS power management.
- **Pending Outdoor Field Baseline**: Continuous GNSS battery consumption and fix cadence during extended locked-screen outdoor walks have not been fully characterized across device models and remain pending dedicated field comparison.
- **User Force-Quit**: If the app is explicitly terminated from the iOS App Switcher, iOS suspends location delivery until the user manually relaunches the app.
- **First Unlock After Reboot**: Due to on-disk data protection (`completeUntilFirstUserAuthentication`), the device must be unlocked at least once after reboot before background wakeups can read or write points.
- **Provisioning Expiry**: Personal free Apple Developer provisioning profiles expire every 7 days, requiring the app to be re-signed and redeployed from Xcode.

## License

- Source code is licensed under the [MIT License](LICENSE).
- App icon assets are adapted from Wikimedia Commons and licensed under [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/) — see [ATTRIBUTION.md](ATTRIBUTION.md).
