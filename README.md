<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="logo-dark.png">
    <img src="logo.png" width="128" height="128" alt="Footsteps logo" />
  </picture>
</p>

<h1 align="center">Footsteps</h1>

<p align="center">
  Raw location → a daily diary. Keep the evidence on your iPhone.
</p>

<p align="center">
  <a href="https://simply-sunny.github.io/footsteps/"><img src="https://img.shields.io/badge/docs-GitHub_Pages-black?style=flat-square&logo=github" alt="Docs"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-black?style=flat-square" alt="License"></a>
  <a href="https://developer.apple.com/ios/"><img src="https://img.shields.io/badge/platform-iOS_17+-black?style=flat-square&logo=apple" alt="iOS 17+"></a>
  <a href="https://swift.org/"><img src="https://img.shields.io/badge/language-Swift-black?style=flat-square&logo=swift" alt="Swift"></a>
</p>

<p align="center">
  <sub>SwiftUI · SwiftData · MapKit · Swift Charts · local-first</sub>
</p>

---

### Highlights

| On-device | Path + Time | 23 / 24 / 25 h |
| :---: | :---: | :---: |
| local history · no app account or cloud sync | observed movement + duration-weighted stays | calendar-day partition, including daylight-saving changes |

Footsteps records raw Core Location observations and reconstructs your day without turning missing data into invented travel. No third-party app dependencies. MapKit may use Apple network services; local-first does not mean every system framework is offline.

### Evidence before inference

```text
Core Location → protected SwiftData store → daily reconstruction → Path / Time
```

- **Raw evidence:** coordinates, timestamps, accuracy, altitude, speed, course, sensor-source flags and reception metadata. Native negative sentinels are preserved.
- **Path:** reconstructed movement and stationary observations. Gaps over the provisional 30-second continuity ceiling, poor fixes and implausible jumps split routes.
- **Time:** radial heat weighted by supported stay duration, not GPS sample count.
- **Day Detail:** observed distance, places, moving time, dwell map, cumulative distance, time by place and the moving / stationary / unknown breakdown.
- **Optional Health:** read steps on demand in segment and day details. Samples belong to the interval where they start; boundary samples are not prorated.

Moving + stationary + unknown = elapsed time. Today is clamped to elapsed time; unknown intervals remain unknown. See [architecture](ARCHITECTURE.md) for the reconstruction rules and their limits.

---

### Quickstart

Requires macOS, Xcode with an iOS 17+ SDK, an Apple signing team and a physical iPhone for background recording. Source-only: no App Store download or prebuilt binary.

```bash
git clone https://github.com/simply-sunny/footsteps.git
cd footsteps
open Footsteps.xcodeproj
```

1. Select the **Footsteps** target → **Signing & Capabilities**. Choose your team, enable automatic signing and set a unique bundle identifier.
2. Enable **Developer Mode** on your iPhone, connect it and select it as the run destination.
3. Run (`⌘R`) and allow location access. For background recording, choose **Always** and enable **Precise Location** in iOS Settings.
4. Open a detail view and tap its Health button if you want step counts. Health access is optional and read-only.

**Explore a day:** use the date capsule to select or scrub dates, switch **Path / Time**, tap map observations for details, or tap the summary for Day Detail. Settings contains **Background Recording** and separate **Developer Diagnostics**.

---

### Know the limits

- **Battery and background continuity:** navigation-grade GNSS is energy-intensive. Extended locked-screen cadence, cellular handoffs and battery impact still need physical-device testing. No sub-2% battery claim.
- **Force-quit and reboot:** force-quitting stops location delivery until relaunch. Unlock once after a reboot so the protected store can be accessed.
- **Provisioning:** free personal profiles expire after 7 days. Re-sign and redeploy; do not delete the app to renew signing if you need its history.
- **Portability:** GPX/GeoJSON export and replay are not shipped yet. No cloud recovery. Preserve any data you need before removing or reinstalling the app.
- **Inference:** between-fix lines and stationary grouping are conservative heuristics, not continuous ground truth or verified venue visits.

See [privacy](PRIVACY.md) and [open issues](https://github.com/simply-sunny/footsteps/issues) for details.

---

### Verification

With Xcode selected (`DEVELOPER_DIR` can point to your installed Xcode):

```bash
# Pure Foundation calendar, validation and geometry checks
xcrun --sdk macosx swiftc Footsteps/TrajectoryMath.swift Footsteps/DayHistory.swift \
  Tests/Task1FoundationTests.swift -o /tmp/footsteps-math
/tmp/footsteps-math

# Compile the app without signing
xcodebuild -project Footsteps.xcodeproj -scheme Footsteps \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

# Choose an available simulator, then run the app test target
xcrun simctl list devices available
xcodebuild -project Footsteps.xcodeproj -scheme Footsteps \
  -destination 'platform=iOS Simulator,id=<SIMULATOR-UUID>' CODE_SIGNING_ALLOWED=NO test
```

Tests cover storage, schema migration, segmentation, calendar boundaries, Health sample ownership and map overlays. The historical-database migration test requires its external fixture; simulator tests do not establish physical-device battery or gesture behavior.

---

### Project structure

```text
Footsteps/LocationManager.swift   Core Location ingestion and permissions
Footsteps/LocationPoint.swift     versioned raw-evidence schemas
Footsteps/TrajectoryMath.swift    validation, segmentation and geometry
Footsteps/DayHistory.swift        day partition and place reconstruction
Footsteps/TrajectoryMapView.swift Path / Time overlays and map interaction
Footsteps/DayDetailView.swift     Swift Charts day analysis
Footsteps/StepCountReader.swift   on-demand Health queries
Tests/                           Foundation checks and Xcode tests
docs/                            GitHub Pages site and bundled assets
scripts/bundle-docs.py            bundle Markdown for zero-fetch tabs
```

---

### Docs

**https://simply-sunny.github.io/footsteps/** — interactive Path / Time preview, setup, privacy and architecture.

Site styles reuse [Sunny Components](https://github.com/simply-sunny/sunny-components) tokens and source-first patterns without adding a React runtime. After changing Markdown, run `python3 scripts/bundle-docs.py` to refresh the reader.

### License

[MIT](LICENSE) · Saunak Karnati · App icon: [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/) — see [attribution](ATTRIBUTION.md). Vendored site assets retain their licenses in [`docs/vendor/`](docs/vendor/).
