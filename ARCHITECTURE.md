# Architecture

Footsteps separates raw evidence from derived history. It uses Apple frameworks, with no third-party app dependencies.

## Record

`LocationManager.swift` receives Core Location fixes with navigation-grade accuracy and no distance filter. It also registers for significant location changes. This is not a low-power-only recorder: continuous updates remain enabled while recording is on.

Each callback persists raw measurements, including negative sensor sentinels, source flags and reception metadata. `LocationPoint.swift` defines the versioned SwiftData schemas and migration plan. `FootstepsApp.swift` opens the protected on-device store; initialization failure is shown instead of silently replacing the database.

## Reconstruct

`TrajectoryMath.swift` validates points for display without deleting raw evidence. It splits routes at unsupported gaps, poor-fix barriers and implausible jumps. The provisional continuity ceiling is 30 seconds. Stationary anchors are bounded to 25 metres so a coarse GPS fix cannot swallow an entire walk.

`DayHistory.swift` partitions the selected calendar day's elapsed time into disjoint moving, stationary and unknown intervals:

```
moving + stationary + unknown = elapsed
```

Calendar boundaries account for 23- and 25-hour daylight-saving days. Today is clamped to the current time. Nearby stays receive neutral place labels; missing time does not become an inferred visit.

## Present

`DailyTrackerView.swift` queries the selected day and offers date navigation, Path/Time selection, settings and detail sheets. `TrajectoryMapView.swift` draws reconstructed movement and grouped places. Time mode uses radial heat weighted by stay duration, not sample density.

`DayDetailView.swift` shows observed distance, places, moving time, a dwell map, cumulative distance, time by place and the day partition. Gaps are not evidence of travel.

## Read steps

`StepCountReader.swift` requests read-only Health access on demand. Cumulative queries assign samples by start time to half-open intervals `[start, end)` so adjacent day queries do not count a boundary sample twice. A sample that crosses a boundary belongs to the interval where it starts; it is not prorated. Health source reconciliation remains HealthKit's job. These counts are not a claim that every step occurred along a GPS segment.

## Verify and known limits

The repository includes Foundation CLI checks and an Xcode test target covering storage migration, segmentation, calendar boundaries, overlays and formatting. Simulator tests do not establish locked-screen GNSS cadence, battery life, cellular-handoff recovery or physical-device gesture quality. Those checks remain tracked in GitHub issues #1 and #2. GPX/GeoJSON export remains tracked in #3.

## Build this documentation site

The site is plain HTML, CSS and JavaScript in `docs/`; the authored stylesheet must stay under 100 lines. Markdown sources are bundled by `python3 scripts/bundle-docs.py`. Vendored marked and DOMPurify render sanitized documents without runtime document fetches. The trajectory preview is SVG drawn from explicitly synthetic data, with no map SDK.
