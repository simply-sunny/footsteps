import Foundation

@main
struct Task2FoundationTests {
    static var failureCount = 0

    static func assertTrue(_ condition: Bool, _ message: String) {
        if !condition {
            print("FAIL: \(message)")
            failureCount += 1
        }
    }

    static func assertFalse(_ condition: Bool, _ message: String) {
        assertTrue(!condition, message)
    }

    static func main() {
        print("Running Task 2 Foundation Tests (Trajectory Segmentation, Discontinuities, Stationary Grouping)...")

        let baseDate = Date(timeIntervalSince1970: 1772900000)

        // 1. Empty & Single Point Trajectories
        let emptySegs = TrajectoryMath.segment(points: [])
        assertTrue(emptySegs.isEmpty, "Empty input must return empty segments")

        let singlePoint = [
            TrajectoryPoint(latitude: 37.7749, longitude: -122.4194, timestamp: baseDate, horizontalAccuracy: 10.0)
        ]
        let singleSegs = TrajectoryMath.segment(points: singlePoint)
        assertTrue(singleSegs.isEmpty, "Single point trajectory must return empty segments (>= 2 points required)")
        let singleAnalysis = TrajectoryMath.analyzeDay(points: singlePoint)
        assertTrue(singleAnalysis.singletons.count == 1, "Single point must be preserved as singleton")
        assertTrue(singleAnalysis.singletons[0].observationDuration == 0.0, "Single point has 0 observation duration")

        // 2. Continuous Trajectory (1Hz Smooth Walking, No Discontinuities)
        var smoothWalkPoints: [TrajectoryPoint] = []
        for i in 0..<60 {
            smoothWalkPoints.append(
                TrajectoryPoint(
                    latitude: 37.7741 + Double(i) * 0.000015, // ~1.6m per second
                    longitude: -122.4191,
                    timestamp: baseDate.addingTimeInterval(Double(i)), // 1Hz sampling (dt = 1.0s)
                    horizontalAccuracy: 5.0
                )
            )
        }
        let smoothSegs = TrajectoryMath.segment(points: smoothWalkPoints)
        assertTrue(smoothSegs.count == 1, "Continuous 1Hz smooth walking should produce exactly 1 segment")
        assertTrue(smoothSegs[0].points.count == 60, "Segment should contain all 60 points")
        assertTrue(smoothSegs[0].startDate == baseDate, "startDate should match first point")
        assertTrue(smoothSegs[0].endDate == baseDate.addingTimeInterval(59), "endDate should match last point")
        assertTrue(smoothSegs[0].duration == 59.0, "duration should be 59 seconds")
        assertTrue(smoothSegs[0].distanceMeters > 50.0, "distanceMeters should be > 50m")

        // 3. Continuity Policy Regression: 40s, 120s, 299s gaps do NOT connect by DEFAULT (<=30s policy)
        // Raw legacy points preserved, explicit override maxTimeGapSeconds connects
        let multiGapPoints = [
            // Walk 1 (2 points, dt = 10s)
            TrajectoryPoint(latitude: 37.7741, longitude: -122.4191, timestamp: baseDate, horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7743, longitude: -122.4193, timestamp: baseDate.addingTimeInterval(10), horizontalAccuracy: 10.0),
            // 40s gap (dt = 40s > 30s default)
            // Walk 2 (2 points, dt = 10s)
            TrajectoryPoint(latitude: 37.7745, longitude: -122.4195, timestamp: baseDate.addingTimeInterval(50), horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7747, longitude: -122.4197, timestamp: baseDate.addingTimeInterval(60), horizontalAccuracy: 10.0),
            // 120s gap (dt = 120s > 30s default)
            // Walk 3 (2 points, dt = 10s)
            TrajectoryPoint(latitude: 37.7749, longitude: -122.4199, timestamp: baseDate.addingTimeInterval(180), horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7751, longitude: -122.4201, timestamp: baseDate.addingTimeInterval(190), horizontalAccuracy: 10.0),
            // 299s gap (dt = 299s > 30s default)
            // Walk 4 (2 points, dt = 10s)
            TrajectoryPoint(latitude: 37.7753, longitude: -122.4203, timestamp: baseDate.addingTimeInterval(489), horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7755, longitude: -122.4205, timestamp: baseDate.addingTimeInterval(499), horizontalAccuracy: 10.0)
        ]

        // By DEFAULT (<=30s threshold): 40s, 120s, 299s gaps do NOT connect -> splits into 4 segments
        let defaultSegs = TrajectoryMath.segment(points: multiGapPoints)
        assertTrue(defaultSegs.count == 4, "40s, 120s, 299s gaps must split into 4 segments by default (actual: \(defaultSegs.count))")
        for (idx, seg) in defaultSegs.enumerated() {
            assertTrue(seg.points.count == 2, "Segment \(idx) must have 2 points")
        }

        let multiGapAnalysis = TrajectoryMath.analyzeDay(points: multiGapPoints)
        assertTrue(multiGapAnalysis.rawCount == 8, "Raw count must preserve all 8 points")
        assertTrue(multiGapAnalysis.usableCount == 8, "All 8 points are usable")
        assertTrue(multiGapAnalysis.gapCount == 3, "Timeline must identify exactly 3 gaps (>30s)")
        assertTrue(abs(multiGapAnalysis.maxGapSeconds - 299.0) < 0.001, "Max gap duration must be 299s")

        // Explicit override (maxTimeGapSeconds: 300s): all gaps (40s, 120s, 299s) connect into 1 segment
        let override300Segs = TrajectoryMath.segment(points: multiGapPoints, maxTimeGapSeconds: 300.0)
        assertTrue(override300Segs.count == 1, "Explicit 300s gap override should connect all 40s/120s/299s gaps into 1 segment")
        assertTrue(override300Segs[0].points.count == 8, "Override segment must contain all 8 points")

        // Explicit override (maxTimeGapSeconds: 100s): connects 40s gap, splits at 120s and 299s gaps -> 3 segments
        let override100Segs = TrajectoryMath.segment(points: multiGapPoints, maxTimeGapSeconds: 100.0)
        assertTrue(override100Segs.count == 3, "Explicit 100s gap override should split at 120s and 299s gaps into 3 segments")

        // 3b. Dwell Must Not Bridge Gaps (40s, 120s, 299s)
        var splitDwellPoints: [TrajectoryPoint] = []
        // Cluster 1: 5 points at 5s intervals (t=0..20) staying within 2m
        for i in 0..<5 {
            splitDwellPoints.append(
                TrajectoryPoint(
                    latitude: 37.7749 + Double(i % 2) * 0.00001,
                    longitude: -122.4194,
                    timestamp: baseDate.addingTimeInterval(Double(i * 5)),
                    horizontalAccuracy: 10.0
                )
            )
        }
        // 40s gap (next point at t=60)
        // Cluster 2: 5 points at 5s intervals (t=60..80) staying within 2m at the same location
        for i in 0..<5 {
            splitDwellPoints.append(
                TrajectoryPoint(
                    latitude: 37.7749 + Double(i % 2) * 0.00001,
                    longitude: -122.4194,
                    timestamp: baseDate.addingTimeInterval(60.0 + Double(i * 5)),
                    horizontalAccuracy: 10.0
                )
            )
        }
        let splitDwellAnalysis = TrajectoryMath.analyzeDay(points: splitDwellPoints)
        assertTrue(splitDwellAnalysis.rawCount == 10, "Raw count must preserve all 10 fixes")
        assertTrue(splitDwellAnalysis.segments.isEmpty, "Stationary dwell points must not produce polylines")
        assertTrue(splitDwellAnalysis.singletons.count == 2, "Stationary dwell must NOT bridge across 40s gap; must produce 2 distinct dwell singletons")
        assertTrue(splitDwellAnalysis.singletons[0].observationDuration == 20.0, "First dwell singleton duration should be 20s")
        assertTrue(splitDwellAnalysis.singletons[1].observationDuration == 20.0, "Second dwell singleton duration should be 20s")

        // 4. Discontinuity: Speed > 50 m/s (180 km/h)
        let speedPoints = [
            // Segment 1 (2 points, dt = 10s)
            TrajectoryPoint(latitude: 37.7741, longitude: -122.4191, timestamp: baseDate, horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7743, longitude: -122.4193, timestamp: baseDate.addingTimeInterval(10), horizontalAccuracy: 10.0),
            // High speed jump (latitude jump ~0.02 deg is ~2.2 km in 5 seconds = 440 m/s > 50 m/s, dt=5s <= 30s)
            // Segment 2 (2 points, dt = 10s)
            TrajectoryPoint(latitude: 37.7940, longitude: -122.4192, timestamp: baseDate.addingTimeInterval(15), horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7942, longitude: -122.4194, timestamp: baseDate.addingTimeInterval(25), horizontalAccuracy: 10.0)
        ]
        let speedSegs = TrajectoryMath.segment(points: speedPoints)
        assertTrue(speedSegs.count == 2, "Speed > 50 m/s should split into 2 segments (actual: \(speedSegs.count))")

        // 5. Discontinuity: Distance Jump > 10 km (dt <= 30s)
        let distanceJumpPoints = [
            TrajectoryPoint(latitude: 37.7741, longitude: -122.4191, timestamp: baseDate, horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7743, longitude: -122.4193, timestamp: baseDate.addingTimeInterval(10), horizontalAccuracy: 10.0),
            // San Jose coordinate (~70km away) at 10s gap (dist > 10km, dt=10s <= 30s)
            TrajectoryPoint(latitude: 37.3382, longitude: -121.8863, timestamp: baseDate.addingTimeInterval(20), horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.3384, longitude: -121.8865, timestamp: baseDate.addingTimeInterval(30), horizontalAccuracy: 10.0)
        ]
        let distSegs = TrajectoryMath.segment(points: distanceJumpPoints)
        assertTrue(distSegs.count == 2, "Distance jump > 10km should split into 2 segments (actual: \(distSegs.count))")

        // 6. Duplicate timestamps: display-only de-duplication retaining raw
        let duplicatePoints = [
            TrajectoryPoint(latitude: 37.7741, longitude: -122.4191, timestamp: baseDate, horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7743, longitude: -122.4193, timestamp: baseDate.addingTimeInterval(10), horizontalAccuracy: 10.0),
            // Duplicate timestamp (dt=0) with coarser accuracy
            TrajectoryPoint(latitude: 37.77435, longitude: -122.41935, timestamp: baseDate.addingTimeInterval(10), horizontalAccuracy: 25.0),
            TrajectoryPoint(latitude: 37.7745, longitude: -122.4195, timestamp: baseDate.addingTimeInterval(20), horizontalAccuracy: 10.0)
        ]
        let dedupedSegs = TrajectoryMath.segment(points: duplicatePoints)
        assertTrue(dedupedSegs.count == 1, "Duplicate timestamps (dt=0) must be de-duplicated for display without splitting segment")
        assertTrue(dedupedSegs[0].points.count == 3, "De-duplicated segment should contain 3 distinct points retaining higher precision fix")
        let dedupAnalysis = TrajectoryMath.analyzeDay(points: duplicatePoints)
        assertTrue(dedupAnalysis.rawCount == 4, "Raw count must preserve all 4 fixes")

        // 6b. Conflicting Distant Coordinates at Same Timestamp (Preserve Barrier & Uncertainty)
        let conflictingSameTimestampPoints = [
            TrajectoryPoint(latitude: 37.7741, longitude: -122.4191, timestamp: baseDate, horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7743, longitude: -122.4193, timestamp: baseDate.addingTimeInterval(10), horizontalAccuracy: 10.0),
            // Conflicting distant coordinate (~2.2km away) reported at exact same timestamp t=10
            TrajectoryPoint(latitude: 37.7940, longitude: -122.4192, timestamp: baseDate.addingTimeInterval(10), horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7942, longitude: -122.4194, timestamp: baseDate.addingTimeInterval(20), horizontalAccuracy: 10.0)
        ]
        let conflictAnalysis = TrajectoryMath.analyzeDay(points: conflictingSameTimestampPoints)
        assertTrue(conflictAnalysis.rawCount == 4, "Raw count must preserve all 4 fixes including conflicting same-timestamp coords")
        assertTrue(conflictAnalysis.segments.count == 2, "Conflicting distant coords at same timestamp must act as barrier and split into 2 segments")
        assertTrue(conflictAnalysis.segments[0].points.count == 2, "First segment has 2 points")
        assertTrue(conflictAnalysis.segments[1].points.count == 2, "Second segment has 2 points")

        // 7. Anchored Stationary Jitter Suppression vs Slow Walk
        var stationaryPoints: [TrajectoryPoint] = []
        for i in 0..<10 {
            let jitterLat = 37.7749 + Double(i % 3) * 0.00002 // ~2 meters jitter
            let jitterLon = -122.4194 + Double(i % 2) * 0.00002
            stationaryPoints.append(
                TrajectoryPoint(
                    latitude: jitterLat,
                    longitude: jitterLon,
                    timestamp: baseDate.addingTimeInterval(Double(i * 10)),
                    horizontalAccuracy: 15.0
                )
            )
        }
        let statAnalysis = TrajectoryMath.analyzeDay(points: stationaryPoints)
        assertTrue(statAnalysis.segments.isEmpty, "Stationary jitter within uncertainty radius must not produce spurious movement segment")
        assertTrue(statAnalysis.singletons.count == 1, "Stationary jitter must produce 1 dwell singleton")
        assertTrue(statAnalysis.singletons[0].observationDuration == 90.0, "Dwell singleton must have supported observation duration of 90s")

        // 7b. Mixed Route: Walking -> Stationary Dwell -> Walking
        var mixedRoutePoints: [TrajectoryPoint] = []
        for i in 0..<5 {
            mixedRoutePoints.append(
                TrajectoryPoint(
                    latitude: 37.7741 + Double(i) * 0.0002,
                    longitude: -122.4191,
                    timestamp: baseDate.addingTimeInterval(Double(i * 10)),
                    horizontalAccuracy: 10.0
                )
            )
        }
        let mrAnchor = mixedRoutePoints.last!
        let mrDwellStart = mrAnchor.timestamp
        for i in 1...20 {
            mixedRoutePoints.append(
                TrajectoryPoint(
                    latitude: mrAnchor.latitude + Double(i % 3) * 0.00002,
                    longitude: mrAnchor.longitude + Double(i % 2) * 0.00002,
                    timestamp: mrDwellStart.addingTimeInterval(Double(i * 10)),
                    horizontalAccuracy: 15.0
                )
            )
        }
        let mrDwellEnd = mrDwellStart.addingTimeInterval(20 * 10)
        for i in 1...4 {
            mixedRoutePoints.append(
                TrajectoryPoint(
                    latitude: mrAnchor.latitude + Double(i) * 0.0002,
                    longitude: -122.4191,
                    timestamp: mrDwellEnd.addingTimeInterval(Double(i * 10)),
                    horizontalAccuracy: 10.0
                )
            )
        }
        let mixedAnalysis = TrajectoryMath.analyzeDay(points: mixedRoutePoints)
        assertTrue(mixedAnalysis.rawCount == 29, "Mixed route must preserve all 29 raw fixes")
        assertTrue(mixedAnalysis.segments.count == 2, "Mixed route must split into 2 segments around stationary dwell")
        assertTrue(mixedAnalysis.singletons.count == 1, "Mixed route must produce 1 stationary dwell singleton")
        assertTrue(abs(mixedAnalysis.singletons[0].observationDuration - 200.0) < 0.1, "Dwell singleton must have 200s duration")
        assertTrue(mixedAnalysis.segments[0].points.count == 5, "First walk segment has 5 points")
        assertTrue(mixedAnalysis.segments[1].points.count == 5, "Second walk segment has 5 points")

        // 8. Poor-Fix Barrier and Outlier Handling
        let mixedPoints = [
            // Segment 1 (2 points)
            TrajectoryPoint(latitude: 37.7741, longitude: -122.4191, timestamp: baseDate, horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7743, longitude: -122.4193, timestamp: baseDate.addingTimeInterval(10), horizontalAccuracy: 10.0),
            // Poor fix barrier (accuracy 250m > 200m)
            TrajectoryPoint(latitude: 37.7744, longitude: -122.4194, timestamp: baseDate.addingTimeInterval(20), horizontalAccuracy: 250.0),
            // Nonfinite & invalid coordinate barriers
            TrajectoryPoint(latitude: Double.nan, longitude: -122.4194, timestamp: baseDate.addingTimeInterval(25), horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 100.0, longitude: -122.4194, timestamp: baseDate.addingTimeInterval(30), horizontalAccuracy: 10.0),
            // Segment 2 (2 points)
            TrajectoryPoint(latitude: 37.7745, longitude: -122.4195, timestamp: baseDate.addingTimeInterval(40), horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7747, longitude: -122.4197, timestamp: baseDate.addingTimeInterval(50), horizontalAccuracy: 10.0)
        ]
        let filteredSegs = TrajectoryMath.segment(points: mixedPoints)
        assertTrue(filteredSegs.count == 2, "Poor-fix barrier must split into 2 segments without bridging")
        assertTrue(filteredSegs[0].points.count == 2, "First segment must have 2 points")
        assertTrue(filteredSegs[1].points.count == 2, "Second segment must have 2 points")

        // 9. Chronological Sorting of Unsorted Input
        let unsortedPoints = [
            TrajectoryPoint(latitude: 37.7745, longitude: -122.4195, timestamp: baseDate.addingTimeInterval(20), horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7741, longitude: -122.4191, timestamp: baseDate, horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7743, longitude: -122.4193, timestamp: baseDate.addingTimeInterval(10), horizontalAccuracy: 10.0)
        ]
        let sortedSegs = TrajectoryMath.segment(points: unsortedPoints)
        assertTrue(sortedSegs.count == 1, "Unsorted input points must be sorted chronologically and segmented")
        assertTrue(sortedSegs[0].points[0].timestamp == baseDate, "First point in segment must have earliest timestamp")
        assertTrue(sortedSegs[0].points[2].timestamp == baseDate.addingTimeInterval(20), "Last point must have latest timestamp")

        // 10. Deterministic Stable ID Generation
        let run1 = TrajectoryMath.segment(points: smoothWalkPoints)
        let run2 = TrajectoryMath.segment(points: smoothWalkPoints)
        assertTrue(run1.count == 1 && run2.count == 1, "Both segmentation runs should produce 1 segment")
        assertTrue(run1[0].id == run2[0].id, "Segment IDs must be completely deterministic across runs (ID: \(run1[0].id))")
        assertFalse(run1[0].id.isEmpty, "Segment ID must not be empty")

        // 11. Step Count Formatting & Degradation
        assertTrue(StepCountReader.formatStepCount(nil) == "Steps unavailable", "Nil steps must degrade to 'Steps unavailable'")
        assertTrue(StepCountReader.formatStepCount(0) == "0 steps", "0 steps format")
        assertTrue(StepCountReader.formatStepCount(1) == "1 step", "1 step singular format")
        assertTrue(StepCountReader.formatStepCount(250) == "250 steps", "250 steps plural format")

        // 12. Duration Minutes Formatting
        assertTrue(StepCountReader.formatDurationMinutes(0) == "1 min", "0s duration must format to 1 min")
        assertTrue(StepCountReader.formatDurationMinutes(45) == "1 min", "45s duration must format to 1 min")
        assertTrue(StepCountReader.formatDurationMinutes(90) == "2 min", "90s duration must format to 2 min")
        assertTrue(StepCountReader.formatDurationMinutes(300) == "5 min", "300s duration must format to 5 min")

        // 13. Time Interval Formatting
        let formattedInterval = StepCountReader.formatTimeInterval(
            start: baseDate,
            end: baseDate.addingTimeInterval(1800),
            locale: Locale(identifier: "en_US"),
            timeZone: TimeZone(identifier: "UTC")!
        )
        assertFalse(formattedInterval.isEmpty, "Time interval must format non-empty string")

        if failureCount > 0 {
            print("Task 2 Foundation Tests FAILED with \(failureCount) failures.")
            exit(1)
        } else {
            print("All Task 2 Foundation Tests Passed Successfully!")
        }
    }
}
