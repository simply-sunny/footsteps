<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Footsteps/Assets.xcassets/AppIcon.appiconset/AppIcon-Dark.png">
    <img src="Footsteps/Assets.xcassets/AppIcon.appiconset/AppIcon-Default.png" width="128" height="128" alt="Footsteps logo" />
  </picture>
</p>

# Footsteps

A minimal, local-first iOS 17+ app that passively records device location and renders real daily trajectory segments.

## Features

- **Passive Background Tracking**: Continuous location monitoring (100m accuracy, 50m distance filter) with significant location change wakeups.
- **Local-First Storage**: Persistent location point history stored locally on-device using SwiftData with encrypted file protection (`completeUntilFirstUserAuthentication`).
- **Segmented Trajectory Overlay**: Pure derived trajectory segmentation with MapKit polyline overlays (`SegmentPolyline`), discontinuity detection, and interactive segment selection.
- **On-Demand HealthKit Steps**: Tapping a trajectory segment presents a compact bottom sheet displaying localized start–end times, duration in minutes, and cumulative HealthKit step counts for the exact segment interval.
- **Privacy-Preserving Degradation**: Gracefully degrades to "Steps unavailable" when steps are denied, unavailable, or on unsupported devices without distinguishing read denial.
- **Day-by-Day Navigation**: Daily tracker UI with date stepping, calendar day boundary calculations, and future date navigation guards.
- **Zero Third-Party Dependencies**: Pure Apple system frameworks (`SwiftUI`, `SwiftData`, `MapKit`, `CoreLocation`, `HealthKit`, `UIKit`).
- **Native iOS 18 Dark Appearance Icon**: Configured asset catalog supporting both default and native iOS 18 dark appearance icon styles.

## Requirements

- iOS 17.0+
- Xcode 15+ (Swift 5.0 mode on Swift 6 toolchain)
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
- **Date Status**: Header displays date selection and permission/tracking status.
- **Trajectory View**: Pan and pinch to zoom over the MapKit canvas; tap individual trajectory segments to highlight them.
- **User Tracking**: Tap the native tracking button to toggle location tracking modes.
- **Location Permission Banner**: Tap the warning banner if location permissions are restricted to open iOS Settings.

## Build

```bash
# Run Foundation math, segmentation, and navigation test suites via CLI
swiftc Tests/Task1FoundationTests.swift Footsteps/TrajectoryMath.swift -o /tmp/task1_test && /tmp/task1_test
swiftc Tests/Task2FoundationTests.swift Footsteps/TrajectoryMath.swift Footsteps/StepCountReader.swift -o /tmp/task2_test && /tmp/task2_test
```

Full app compilation and UI/MapKit test execution require Xcode with the iOS 17+ SDK (`Cmd + B` / `Cmd + U`).

## Limitations

- **Source-Only Release**: Provided as an uncompiled source project intended for personal self-signed deployment; no prebuilt binaries or App Store distribution.
- **User Force-Quit**: If the app is explicitly terminated from the iOS App Switcher, iOS suspends location delivery until the user manually relaunches the app.
- **First Unlock After Reboot**: Due to on-disk data protection (`completeUntilFirstUserAuthentication`), the device must be unlocked at least once after reboot before background wakeups can read or write points.
- **Unverified CLI Runtime**: Full iOS build, MapKit rendering, CoreLocation hardware updates, and locked-screen background walks are unverified in headless CLI environments without Xcode/Simulator runtime.
- **Provisioning Expiry**: Personal free Apple Developer provisioning profiles expire every 7 days, requiring the app to be re-signed and redeployed from Xcode.

## License

- Source code is licensed under the [MIT License](LICENSE).
- App icon assets are adapted from Wikimedia Commons and licensed under [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/) — see [ATTRIBUTION.md](ATTRIBUTION.md).
