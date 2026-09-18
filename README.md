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
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-black?style=flat-square" alt="License"></a>
  <a href="https://developer.apple.com/ios/"><img src="https://img.shields.io/badge/platform-iOS_17+-black?style=flat-square&logo=apple" alt="iOS 17+"></a>
  <a href="https://swift.org/"><img src="https://img.shields.io/badge/language-Swift-black?style=flat-square&logo=swift" alt="Swift"></a>
</p>

<p align="center">
  <sub>SwiftUI · SwiftData · MapKit · Swift Charts · local-first</sub>
</p>

---

Footsteps records raw Core Location observations and reconstructs your day. Everything stays on-device — no account, no cloud sync.

- **Path:** movement and stationary observations; gaps and poor fixes split routes.
- **Time:** radial heat weighted by stay duration.
- **Day Detail:** distance, places, moving time, moving / stationary / unknown breakdown.
- **Health:** steps on demand, read-only.

### Quickstart

Requires macOS, Xcode (iOS 17+ SDK), an Apple signing team and a physical iPhone.

```bash
git clone https://github.com/simply-sunny/footsteps.git
open Footsteps.xcodeproj
```

Set your team and bundle ID under **Signing & Capabilities**, enable **Developer Mode** on your iPhone, then run (`⌘R`). Choose **Always** location access and enable **Precise Location** for background recording.

### License

[MIT](LICENSE) · Saunak Karnati · App icon: [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/) — see [attribution](ATTRIBUTION.md).
