# User-Facing History & Native UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a quiet, native iOS personal location diary interface with Path/Time map modes, duration-weighted dwell heatmap, separate day detail screen (headline metrics, dwell mini-map, disjoint cumulative distance chart, top-5 place chart, time partition donut), and pure Foundation `DayHistory` math models.

**Architecture:** Pure Foundation `DayHistory` model consumes existing `TrajectoryMath.analyzeDay` output; computes non-overlapping time partitions (moving/stationary/unknown), conservative anchored place clustering, and disjoint cumulative distance series. SwiftUI views (`DailyTrackerView`, `DayDetailView`, `TrajectoryMapView`) provide quiet full-bleed MapKit presentation with native Swift Charts and sequestered developer diagnostics.

**Tech Stack:** Swift 5.9+, SwiftUI, MapKit, Swift Charts, CoreLocation, SwiftData (unmodified V1/V2 schemas).

**Spec:** `docs/superpowers/specs/2026-09-09-user-facing-history-design.md`

## Global Constraints
- Preserve Release bundle identifier `sunnny.footsteps.app`.
- Keep existing raw schemas (`LocationSchemaV1`, `LocationSchemaV2`) and location ingestion pipeline intact.
- Zero third-party dependencies.
- No network geocoding or fabricated place names.
- Never clamp negative totals to hide interval overlap: use exact non-overlapping interval math.
- Time partition ($T_{\text{moving}} + T_{\text{stationary}} + T_{\text{unknown}}$) must equal total day elapsed time.
- Time mode (heatmap) overlay must be weighted strictly by stay duration, not raw point density.

---

### Task 1: Mathematical Day History Engine (`DayHistory.swift`)

**Files:**
- Create: `Footsteps/DayHistory.swift`
- Test: `Tests/DayHistoryTests.swift`
- Project: `Footsteps.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `TrajectoryPoint`, `TrajectorySegment`, `TrajectorySingleton`, `TrajectoryDayAnalysis`, `TrajectoryMath`
- Produces: `DayHistory`, `DayStay`, `DayPlace`, `DayIntervalKind`, `TimePartition`, `CumulativeDistanceSegment`

- [x] **Step 1: Write the failing unit tests for DayHistory**
Create `Tests/DayHistoryTests.swift` covering:
- Empty day (100% unknown elapsed)
- Singleton observation (0 stay duration, single fix classification)
- Walk - Stay - Walk partition ($T_{\text{moving}} + T_{\text{stationary}} + T_{\text{unknown}} == T_{\text{elapsed}}$)
- 40s/120s/299s gaps and poor-fix barriers (broken cumulative lines, time marked unknown)
- DST spring (23h) and fall (25h) elapsed calculation
- Today elapsed clamping to `now` and future point rejection
- Conservative place grouping across repeated visits without bridging gaps
- Sample rate invariance of stay duration

- [x] **Step 2: Run test to verify it fails**
Run: `DEVELOPER_DIR=/Applications/Xcode-27.0.0-Beta.6.app/Contents/Developer xcodebuild -project Footsteps.xcodeproj -scheme Footsteps -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:FootstepsTests/DayHistoryTests test`
Expected: Build FAIL or missing DayHistory type.

- [x] **Step 3: Implement `DayHistory.swift`**
Create `Footsteps/DayHistory.swift` with pure Foundation structures and math algorithms:
- `DayStay`: center coordinate, arrival bounds, departure bounds, duration, anchor radius.
- `DayPlace`: stable identifier, display label ("Place 1", "Place 2"), total duration, visit count, center coordinate.
- `DayIntervalKind`: `.moving`, `.stationary`, `.unknown`.
- `TimeIntervalPartition`: start, end, kind.
- `CumulativeDistancePoint`: timestamp, distanceMeters, isBreak.
- `DayHistory.build(points:selectedDate:now:calendar:)`:
  1. Filter points to $[T_{\text{start}}, \min(T_{\text{end}}, \text{now})]$.
  2. Execute `TrajectoryMath.analyzeDay`.
  3. Form non-overlapping moving and stationary intervals.
  4. Derive unknown intervals as interval complement of $(M \cup S)$ over $[T_{\text{start}}, T_{\text{start}} + T_{\text{elapsed}}]$.
  5. Cluster stays into `DayPlace` using conservative spatial proximity (<= 65m).
  6. Generate disjoint cumulative distance points breaking at all unknown intervals.

- [x] **Step 4: Register files in `Footsteps.xcodeproj` and run tests**
Run: `DEVELOPER_DIR=/Applications/Xcode-27.0.0-Beta.6.app/Contents/Developer xcodebuild -project Footsteps.xcodeproj -scheme Footsteps -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:FootstepsTests/DayHistoryTests test`
Expected: PASS all DayHistoryTests.

---

### Task 2: Duration-Weighted Heatmap & Native MapKit Overlays (`TrajectoryMapView.swift`)

**Files:**
- Modify: `Footsteps/TrajectoryMapView.swift`
- Test: `Tests/UIAndMapTests.swift`

**Interfaces:**
- Consumes: `DayHistory`, `DayStay`, `TrajectorySegment`, `TrajectoryPoint`
- Produces: `TrajectoryMapView` with `MapDisplayMode` (`.path`, `.time`), `StayNodeOverlay`, `TimeHeatmapOverlayRenderer`

- [x] **Step 1: Write failing tests for Map Mode and Heatmap weighting**
Add unit/snapshot tests in `Tests/UIAndMapTests.swift` verifying:
- Path mode overlays contain polylines and stay nodes.
- Time mode overlays contain duration-weighted heat overlays and hide polylines.
- Heat intensity/radius scales with duration and does not change when extra 1Hz fixes are inserted.

- [x] **Step 2: Run test to verify failure**
Run: `DEVELOPER_DIR=/Applications/Xcode-27.0.0-Beta.6.app/Contents/Developer xcodebuild -project Footsteps.xcodeproj -scheme Footsteps -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:FootstepsTests/UIAndMapTests test`
Expected: FAIL due to missing MapDisplayMode / stay overlay types.

- [x] **Step 3: Implement Map Display Modes and Overlays in `TrajectoryMapView.swift`**
- Define `public enum MapDisplayMode { case path, time }`.
- Implement `StayCircleOverlay`: carries `DayStay` reference, custom radius scaled by log duration (e.g. 15m to 60m).
- Implement `DwellHeatOverlay` & `DwellHeatRenderer`: smooth gradient rendering from center to radius proportional to $\sqrt{\text{duration}}$, providing true time-weighted heat without relying on raw point density.
- Update `TrajectoryMapView.Coordinator` to support mode switching, selection highlights, and forgiving touch hit-testing for stays and segments.

- [x] **Step 4: Run tests to verify they pass**
Run: `DEVELOPER_DIR=/Applications/Xcode-27.0.0-Beta.6.app/Contents/Developer xcodebuild -project Footsteps.xcodeproj -scheme Footsteps -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:FootstepsTests/UIAndMapTests test`
Expected: PASS.

---

### Task 3: Day Detail View with Swift Charts (`DayDetailView.swift`)

**Files:**
- Create: `Footsteps/DayDetailView.swift`
- Project: `Footsteps.xcodeproj/project.pbxproj`
- Test: `Tests/UIAndMapTests.swift`

**Interfaces:**
- Consumes: `DayHistory`
- Produces: `DayDetailView`

- [x] **Step 1: Write tests for DayDetailView data formatting and charts**
Add tests in `Tests/UIAndMapTests.swift` verifying:
- Formatting of distance (meters vs kilometers), durations (hours and minutes), and place counts.
- Disjoint cumulative distance series handling.
- Top-5 places truncation and duration sorting.
- Donut chart data slices (Stationary, Moving, Unknown) sum to 100%.

- [x] **Step 2: Run test to verify failure**
Run: `DEVELOPER_DIR=/Applications/Xcode-27.0.0-Beta.6.app/Contents/Developer xcodebuild -project Footsteps.xcodeproj -scheme Footsteps -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:FootstepsTests/UIAndMapTests test`
Expected: FAIL due to missing DayDetailView.

- [x] **Step 3: Implement `DayDetailView.swift`**
Construct the 5 required sections in strict order:
1. **Headline**: Observed Distance, Place Count, Moving Duration.
2. **WHERE MY TIME WENT**: Compact dwell mini-map (`MKMapView` non-interactive snapshot showing stays).
3. **MY DAY**: Swift Charts `Chart` with `LineMark` / `PointMark` rendering disjoint segments across gaps.
4. **TIME BY PLACE**: Swift Charts `Chart` with `BarMark` showing top 5 places ranked by dwell time.
5. **DAY BREAKDOWN**: Swift Charts `Chart` with `SectorMark` showing stationary / moving / unknown breakdown with legend.

- [x] **Step 4: Register `DayDetailView.swift` in Xcode project and run tests**
Run: `DEVELOPER_DIR=/Applications/Xcode-27.0.0-Beta.6.app/Contents/Developer xcodebuild -project Footsteps.xcodeproj -scheme Footsteps -destination 'platform=iPhone 17 Pro Max' test`
Expected: PASS.

---

### Task 4: Primary Quiet Interface & Settings (`DailyTrackerView.swift`)

**Files:**
- Modify: `Footsteps/DailyTrackerView.swift`
- Test: `Tests/UIAndMapTests.swift`

**Interfaces:**
- Consumes: `DayHistory`, `DayDetailView`, `TrajectoryMapView`, `LocationManager`
- Produces: `DailyTrackerView`, `StayDetailCardView`, `UserSettingsView`, `DeveloperDiagnosticsView`

- [x] **Step 1: Write tests for navigation, gestures, and settings separation**
Verify:
- Date picker modal presentation and swipe gesture boundary constraints.
- Future date navigation guard.
- Summary tap triggers detail presentation.
- Normal settings does not display raw sensor diagnostics.
- Developer diagnostics accessible via dedicated entry.

- [x] **Step 2: Run test to verify failure**
Run: `DEVELOPER_DIR=/Applications/Xcode-27.0.0-Beta.6.app/Contents/Developer xcodebuild -project Footsteps.xcodeproj -scheme Footsteps -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:FootstepsTests/UIAndMapTests test`
Expected: FAIL.

- [x] **Step 3: Implement Quiet UI in `DailyTrackerView.swift`**
- Top Bar: Day Summary Capsule + Path|Time Picker.
- Full Bleed Map with custom bottom overlay.
- Bottom Floating Bar: Recenter button, Date scrubbing capsule + date picker, Settings button.
- Clean stay card on stay tap (observed bounds, duration, place label).
- Separate `UserSettingsView` with clear privacy controls, and hidden `DeveloperDiagnosticsView`.

- [x] **Step 4: Run full test suite and verify UI layout**
Run: `DEVELOPER_DIR=/Applications/Xcode-27.0.0-Beta.6.app/Contents/Developer xcodebuild -project Footsteps.xcodeproj -scheme Footsteps -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test`
Expected: All tests PASS.

---

### Task 5: Simulator Verification & Layout Inspection

**Files:**
- Update: `.pi/WORKING_STATE.md`, `README.md`

- [x] **Step 1: Launch simulator and capture screenshots**
Launch app on simulator, trigger summary detail sheet, capture screenshot, inspect layout for iPhone 13 Pro Max / 17 Pro Max aspect ratio.
- [x] **Step 2: Verify test pass rates and update documentation**
Ensure zero warnings/regressions, update working state and README.
