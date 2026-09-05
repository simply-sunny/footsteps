# Task Brief: Task 2 — MapKit Heatmap Overlay, DailyTrackerView, UI Integration & Documentation

## Goal
Implement the MapKit daily density grid overlay (`HeatmapMapView`), the single-screen SwiftUI tracker interface (`DailyTrackerView`), pure Foundation grid tests, iOS UI tests, and the project `README.md`.

## Binding Requirements & Constraints
- **Platform & Toolchain**: iOS 17+, Swift 5 language mode (`SWIFT_VERSION = 5.0`) on Swift 6 toolchain, zero external dependencies.
- **Heatmap Visualization**:
  - `HeatmapMapView: UIViewRepresentable` wrapping `MKMapView`.
  - Renders custom `DensityPolygon` overlays with alpha-blended `MKPolygonRenderer` (blue fill, intensity-scaled alpha: `min(max(intensity * 0.7 + 0.15, 0.2), 0.85)`).
  - Automatically adjusts map region to frame the day's points when available.
- **Daily Tracker View**:
  - Main SwiftUI interface with top date navigation header.
  - "< (Previous Day)" button decrements day by 1.
  - "> (Next Day)" button increments day by 1; strictly **disabled** when viewing today (`HeatmapGridMath.isToday`).
  - Displays formatted date header and count of points recorded on that day.
  - Displays warning banner linking to `UIApplication.openSettingsURLString` if location permissions are denied/restricted.
  - Queries SwiftData points strictly for the selected calendar day `[startOfDay, nextStartOfDay)` using `HeatmapGridMath.dayInterval`.
- **Documentation**: Comprehensive `README.md` explaining architecture, build instructions, Simulator location simulation (`Freeway Drive`), and physical device verification.

## Exact Shared Interfaces

```swift
// Footsteps/HeatmapMapView.swift
import SwiftUI
import MapKit

public final class DensityPolygon: MKPolygon {
    public var intensity: Double = 1.0
}

public struct HeatmapMapView: UIViewRepresentable {
    public let points: [LocationPoint]
    public init(points: [LocationPoint])
    public func makeUIView(context: Context) -> MKMapView
    public func updateUIView(_ mapView: MKMapView, context: Context)
    public func makeCoordinator() -> Coordinator
}
```

```swift
// Footsteps/DailyTrackerView.swift
import SwiftUI
import SwiftData
import CoreLocation

public struct DailyTrackerView: View {
    public init()
    public var body: some View { ... }
}
```

## Files to Create
1. `Footsteps/HeatmapMapView.swift`: MapKit `UIViewRepresentable` and density renderer.
2. `Footsteps/DailyTrackerView.swift`: SwiftUI screen with date browsing and permission warning.
3. `Tests/Task2FoundationTests.swift`: Pure Foundation test runner for grid math and day navigation.
4. `Tests/UIAndMapTests.swift`: XCTest suite for day filtering and map overlay creation.
5. `README.md`: Project overview, build instructions, and verification guide.

## Verification
```bash
swiftc Tests/Task2FoundationTests.swift Footsteps/HeatmapGridMath.swift -o /tmp/task2_test && /tmp/task2_test
```
