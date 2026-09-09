# Maximum-Fidelity Footsteps Implementation Plan

## Overview & Execution Constraints
- **Goal**: Implement maximum-fidelity location collection, raw metadata preservation (including native negative sentinels), zero-loss ingestion, safe SwiftData schema migration, anchored uncertainty-aware stationary grouping, singleton preservation with supported observation duration, stable map viewport, diagnostics map overlay, and precise authorization recovery UI.
- **Developer Environment**: `DEVELOPER_DIR=/Applications/Xcode-27.0.0-Beta.6.app/Contents/Developer`.
- **Bundle Identifiers**: Preserve `sunny.footsteps.app` (Debug) and `sunnny.footsteps.app` (Release).
- **Database Safety**: Production database is never reset; migration testing is verified using an isolated historical store fixture (via `FOOTSTEPS_HISTORICAL_STORE_PATH` or sandbox documents) and synthetic stress benchmarks. No coordinates or private user data committed.
- **Verification Rule**: Every task must be verified with automated test executions before proceeding.

---

## Execution Verification Log

### Automated Test Suite Execution
Command:
```bash
export DEVELOPER_DIR=/Applications/Xcode-27.0.0-Beta.6.app/Contents/Developer
xcrun xcodebuild test -project Footsteps.xcodeproj -scheme Footsteps -destination 'platform=iOS Simulator,name=iPhone 17'
```
Result: `** TEST SUCCEEDED **` (43 tests passed)
- `LocationAndStorageTests` (13 tests passed):
  - `testActualHistoricalDBCopyMigration`: Verified historical records migrated from historical store copy without data loss.
  - `testAuthorizationRefresh`: Verified authorization state and precision refresh on active scene phase.
  - `testCoordinateValidation`: Verified boundary, non-finite, and NaN guards.
  - `testDirectoryFileProtection`: Verified completeUntilFirstUserAuthentication attribute.
  - `testDiskPersistenceAndReadbackAcrossContainers`: Verified disk readback.
  - `testLocationManagerConfiguration`: Verified BestForNavigation, zero distance filter, fitness activity type.
  - `testMetadataStampingAndSentinelPreservation`: Verified raw `-1` sentinels preserved, session ID and receivedTimestamp stamped.
  - `testPersistedTrackingDisabledFlag`: Verified user defaults tracking toggle.
  - `testRawIngestionSavesAllFixes`: Verified coarse fixes (>200m) persisted at database boundary.
  - `testTrackingDecisionLogic`: Verified state machine tracking start/stop logic.
  - `testTransientLocationUnknownDiagnostics`: Verified CLError.locationUnknown counted and stamped in telemetry.
  - `testV1toV2SchemaMigrationPreservesExistingRows`: Verified synthetic V1 to V2 migration with nil auxiliaries.
  - `testV1toV2SchemaMigrationStressBenchmark`: Verified 5,000-row migration in <0.3s without lock contention.
- `UIAndMapTests` (30 tests passed):
  - `testDayIntervalFiltering`: Verified half-open [start, end) calendar filtering.
  - `testDayNavigationAndFutureGuard`: Verified previous/next day stepping and future date guard.
  - `testDebugOverlayGeneratesAnnotationsForRawPoints`: Verified diagnostics map overlay adds accuracy circles and classification badges.
  - `testDefaultContinuityPolicyAndGapRegression`: Verified default 30-second continuity threshold and gap detection.
  - `testDuplicateTimestampDoesNotSplitSegment`: Verified duplicate timestamps (dt=0) de-duplicated for display without breaking continuous paths.
  - `testDurationMinutesFormatting`: Verified duration string formatting.
  - `testEmptyDayOverlay`: Verified exact empty state label "No data for this day.".
  - `testGapsAcrossPoorObservationsAreCounted`: Verified gaps across poor fixes detected in raw timeline.
  - `testInvalidQueryIntervalGuard`: Verified invalid date intervals return nil steps safely.
  - `testMapViewCoordinatorHitTestingAndSelection`: Verified segment and singleton selection.
  - `testMixedRouteWalkingStationaryDwellWalking`: Verified mixed sequence of walking, dwell grouping, and walking.
  - `testNegativeCoordinatesAndAntimeridianPolyline`: Verified negative coordinate rendering.
  - `testNilIsBackgroundCountedAsUnknownNotForeground`: Verified nil isBackground tracked as unknown lifecycle.
  - `testNonPhysicalSpeedJump`: Verified speed > 50m/s splits segments.
  - `testNormalizedDayIdentity`: Verified calendar day identity hashing.
  - `testOverlayPreservesSingletonsAndSegments`: Verified polylines and uncertainty circles generated.
  - `testPolylineRendererAndSelectionStyling`: Verified selection highlight styling.
  - `testPoorFixBarrierSplitsSegments`: Verified poor-fix barrier (>200m) splits segments without bridging.
  - `testSameTimestampConflictingDistantCoordinates`: Verified simultaneous conflicting distant coordinates handled without non-physical jumps.
  - `testSamplePredicateConstruction`: Verified HealthKit predicate generation.
  - `testSingletonPreservation`: Verified isolated singletons preserved.
  - `testSlowCumulativeWalkingNotSwallowed`: Verified slow cumulative walk preserved as multi-point segment.
  - `testSmooth1HzWalkingContinuous`: Verified continuous high-cadence walking forms single unbroken segment.
  - `testStationaryDwellDoesNotCrossGap`: Verified dwell duration does not span across gaps.
  - `testStationaryUncertaintyJitterSuppression`: Verified stationary jitter grouped into dwell observation with duration.
  - `testStepCountFormatting`: Verified step count localized formatting.
  - `testTimeIntervalFormatting`: Verified localized time range formatting.
  - `testTrajectoryDayAnalysisMetrics`: Verified raw/usable/outlier counts, median accuracy, max gap duration.
  - `testTrajectorySegmentationAndOverlayGeneration`: Verified polyline bounds and coordinate counts.
  - `testViewportFramingOnlyOnDateChange`: Verified viewport framing occurs only on date navigation.

### Physical Installation & Ingestion Verification
- **Upgrade Verification**: Signed Release build (`sunnny.footsteps.app`) installed over existing on-device installation.
- **Data Integrity**: Pre- and post-launch database verification confirmed 141 legacy records preserved intact (including exact coordinates, timestamps, and horizontal accuracy) with valid database integrity.
- **Post-Launch Ingestion**: 149 total records observed post-launch (8 newly ingested fixes: 5 received with application state active, 3 received with application state non-active).
- **Lifecycle & Background Distinction**: `isBackground` reflects `UIApplication.shared.applicationState != .active` at reception time; non-active reception confirms non-foreground ingestion during execution transitions, but is not equated with unthrottled or prolonged locked-screen background tracking. Full locked-screen outdoor tracking and battery consumption characteristics remain pending physical walk validation.

### Standalone Mathematical Foundation Tests
Commands:
```bash
xcrun swiftc Footsteps/TrajectoryMath.swift Footsteps/StepCountReader.swift Tests/Task1FoundationTests.swift -o /tmp/test1 && /tmp/test1
xcrun swiftc Footsteps/TrajectoryMath.swift Footsteps/StepCountReader.swift Tests/Task2FoundationTests.swift -o /tmp/test2 && /tmp/test2
```
Result: All foundation tests passed with 0 failures.

### Build & Bundle Identifier Verification
- **Release Build**: `xcrun xcodebuild build -project Footsteps.xcodeproj -scheme Footsteps -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO` -> `** BUILD SUCCEEDED **` (`sunnny.footsteps.app` verified)
- **Debug Build**: `xcrun xcodebuild build -project Footsteps.xcodeproj -scheme Footsteps -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17'` -> `** BUILD SUCCEEDED **` (`sunny.footsteps.app` verified)
