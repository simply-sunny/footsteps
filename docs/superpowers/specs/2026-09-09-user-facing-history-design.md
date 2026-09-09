# User-Facing History & Native UI Design Specification

## Goal & Architecture Overview

Transform Footsteps from an engineering telemetry inspector into a quiet, high-fidelity personal location diary on native iOS (SwiftUI + MapKit + Swift Charts). Preserve all raw sensor capture, versioned schemas (V1/V2), and underlying ingestion pipelines unchanged without third-party dependencies or background battery optimizations.

The architecture cleanly divides the system into:
1. **Raw Observation Layer (`LocationPoint.swift`, `LocationManager.swift`)**: Unaltered CoreLocation stream preservation.
2. **Trajectory Reconstruction Layer (`TrajectoryMath.swift`)**: Anchored stationary dwell extraction, poor-fix barrier enforcement, display deduplication.
3. **Derived History Model (`DayHistory.swift`)**: Pure Foundation layer computing mathematically rigorous day partitions (moving, stationary, unknown), disjoint cumulative distance series, conservative anchored place grouping, and DST/today elapsed accounting.
4. **User-Facing UI Layer (`DailyTrackerView.swift`, `TrajectoryMapView.swift`, `DayDetailView.swift`)**:
   - Full-bleed quiet map with bottom floating controls (Recenter, Date scrub/picker, Settings).
   - Path vs. Time (Heatmap) overlay toggle.
   - Time mode renders true time-duration-weighted heat overlays (via custom `MKOverlayRenderer` or multi-radius gradient overlays), independent of raw sample count.
   - Stay tap cards with observed arrival/departure bounds and durations.
   - Separate Day Detail sheet presenting the 5 required sections in exact sequence.
   - Dedicated Settings view with Developer Diagnostics sequestered behind explicit access.

---

## 1. Derived History Model (`DayHistory.swift`)

### Mathematical Partition of Time
For any queried calendar day $D$ bounded by $[T_{\text{start}}, T_{\text{end}}]$ in the device's local calendar (accounting for 23h spring DST, 25h fall DST, or 24h standard days):
- For past days: $T_{\text{elapsed}} = T_{\text{end}} - T_{\text{start}}$.
- For the current day (today): $T_{\text{elapsed}} = \max(0, \min(T_{\text{end}}, \text{now}) - T_{\text{start}})$.
- For future days: $T_{\text{elapsed}} = 0$.

All raw points outside $[T_{\text{start}}, \min(T_{\text{end}}, \text{now})]$ are strictly discarded prior to analysis.

The elapsed time is partitioned into three mutually disjoint sets of intervals whose durations sum exactly to $T_{\text{elapsed}}$:
$$T_{\text{elapsed}} = T_{\text{moving}} + T_{\text{stationary}} + T_{\text{unknown}}$$

1. **Moving Intervals ($M$)**: Formed from continuous trajectory segments ($dt \le 30\text{s}$, displacement $> \text{anchorRadius}$, speed $\le 50\text{m/s}$). Each segment $[t_a, t_b]$ has moving duration $t_b - t_a$.
2. **Stationary Intervals ($S$)**: Formed from supported dwell episodes ($dt \le 30\text{s}$, displacement $\le \text{anchorRadius}$, duration $\ge 60\text{s}$ or grouped stay). Each stay $[t_s, t_e]$ has stationary duration $t_e - t_s$. Isolated singletons ($count = 1$) have stationary duration $0$.
3. **Unknown Intervals ($U$)**: The complement of $(M \cup S)$ over $[T_{\text{start}}, \text{start} + T_{\text{elapsed}}]$. This includes:
   - Time before the first valid observation: $[T_{\text{start}}, t_{\text{first}}]$.
   - Time after the last valid observation: $[t_{\text{last}}, T_{\text{start}} + T_{\text{elapsed}}]$.
   - Unobserved time gaps ($dt > 30\text{s}$) between valid fixes.
   - Interval gaps created by poor-fix barriers (horizontal accuracy $> 200\text{m}$).

No duration is ever clamped to hide overlap; non-overlapping interval union and set subtraction guarantees mathematical consistency.

### Conservative Place Grouping (`DayPlace`)
- Stays located within an anchored spatial radius (e.g. 65 meters) are grouped deterministically into numbered places ("Place 1", "Place 2", etc., ordered by first arrival) or neutral coordinates.
- No network geocoding or fabricated venue names are used.
- Stays across unobserved gaps are grouped to the same place if spatially coincident, but the gap time remains strictly classified as `unknown`.
- Place IDs are deterministically anchored to avoid reassignment when new fixes arrive.

### Cumulative Distance Series
- Cumulative distance is computed along moving segments only (excluding dwell jitter and jump chords).
- The cumulative distance series is partitioned across **every** unknown gap ($dt > 30\text{s}$ or poor-fix barriers) and dwell episode:
  - During moving segments: distance increases monotonically.
  - During supported stationary stays: distance is flat.
  - Across unknown gaps: the line is disconnected / broken to prevent false interpolation.

---

## 2. User Interface Specification

### A. Primary Map Screen (`DailyTrackerView.swift` & `TrajectoryMapView.swift`)
- **Visuals**: Quiet, full-bleed MapKit map. No raw GPS dots, accuracy rings, or telemetry in normal view.
- **Top Bar**:
  - Subtle Day Summary capsule button: e.g. `"2.4 km · 3 places · 42m moving"`. Tapping opens the Day Detail sheet.
  - Path | Time segmented toggle (top trailing or floating).
- **Bottom Controls Bar**:
  - Floating translucent bar with:
    1. **Recenter Button**: Fits map viewport to the day's active bounds (or current location if empty).
    2. **Date Control**:
       - Left / Right step buttons with future-day guard.
       - Center date title button: tapping presents native `DatePicker` modal/popover.
       - Horizontal swipe / scrub gesture on the date capsule to quickly step through days (isolated from MapKit pan gestures).
    3. **Settings Button**: Opens user settings.
- **Map Overlays**:
  - **Path Mode**: Renders smooth blue trajectory lines for moving segments + duration-proportional circular nodes for stationary stays.
  - **Time Mode (Heatmap)**: Renders time-weighted heat overlay where overlay intensity/radius is governed strictly by reconstructed stay duration (e.g., $10\text{min}$ vs $2\text{hr}$), completely invariant to raw sample rate or fix density.
- **Interaction**:
  - Tapping a stay node displays a neutral card with: Place label, observed arrival & departure bounds (e.g. `"Observed 10:14 AM – 11:02 AM"`), and duration (`"48 min"`).
  - Tapping an isolated single fix displays `"Single observation (no stay duration inferred)"`.

### B. Day Detail Screen (`DayDetailView.swift`)
A modal sheet presented upon tapping the summary bar, structured in strict sequence:
1. **Headline Metric Row**:
   - Total Observed Distance (e.g., `3.8 km` or `520 m`).
   - Visited Places Count (e.g., `4 places`).
   - Active Moving Duration (e.g., `1h 12m`).
2. **"WHERE MY TIME WENT" (Dwell Mini-Map)**:
   - Compact non-interactive mini MapKit view highlighting the day's dwell locations with duration-weighted heat rings.
3. **"MY DAY" (Cumulative Distance Chart)**:
   - Swift Charts line graph displaying cumulative distance over time of day (0:00 to 24:00 or elapsed).
   - Renders disjoint line segments across gaps and flat plateaus during dwell episodes.
4. **"TIME BY PLACE" (Top-5 Places Bar Chart)**:
   - Swift Charts horizontal bar chart displaying top 5 places ranked by total dwell duration.
5. **"DAY BREAKDOWN" (Time Partition Donut Chart)**:
   - Swift Charts SectorMark / Donut chart showing:
     - Stationary (Dwell)
     - Moving
     - Unknown (Unrecorded / Gaps)
   - Accompanying legend with exact duration and percentage values.

### C. Settings & Developer Diagnostics
- **Normal Settings**:
  - Background tracking toggle.
  - CoreLocation permission status & precise accuracy recovery button.
  - About / Storage metrics.
- **Developer Diagnostics Entry**:
  - Hidden behind a developer-accessible button / long-press gesture in Settings.
  - Contains all detailed raw fix counts, gap distribution, sensor flags, simulated flags, and live raw overlay toggles.

---

## 3. Testing Strategy
- Unit tests for `DayHistory`:
  1. Empty day $\rightarrow 100\%$ unknown elapsed time.
  2. Singleton observation $\rightarrow 0$ stay duration, distance $0$, rest unknown.
  3. Continuous walk $\rightarrow$ moving duration equals span, stationary $0$.
  4. Walk - Stay - Walk $\rightarrow$ exact non-overlapping partition summing to day elapsed.
  5. Missing time gaps (40s, 120s, 299s) $\rightarrow$ classified as unknown, breaks cumulative distance series.
  6. Poor-fix barrier (>200m) $\rightarrow$ breaks segments and cumulative distance.
  7. DST transitions $\rightarrow$ 23h spring (82,800s) and 25h fall (90,000s) elapsed totals.
  8. Today elapsed $\rightarrow$ clamped to `now`, future samples excluded.
  9. Repeated visits to same location $\rightarrow$ grouped to same `DayPlace` without bridging intermediate missing time.
  10. Duration-weighted heatmap values $\rightarrow$ invariant to sample rate (100 fixes over 10m == 2 fixes over 10m).
- UI and Map tests for gesture isolation, Path vs Time switching, and navigation controls.
