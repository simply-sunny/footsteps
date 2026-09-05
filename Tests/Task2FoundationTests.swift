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
        print("Running Task 2 Foundation Tests (Trajectory Segmentation, Discontinuities, Deterministic IDs)...")

        let baseDate = Date(timeIntervalSince1970: 1772900000)

        // 1. Empty & Single Point Trajectories
        let emptySegs = TrajectoryMath.segment(points: [])
        assertTrue(emptySegs.isEmpty, "Empty input must return empty segments")

        let singlePoint = [
            TrajectoryPoint(latitude: 37.7749, longitude: -122.4194, timestamp: baseDate, horizontalAccuracy: 10.0)
        ]
        let singleSegs = TrajectoryMath.segment(points: singlePoint)
        assertTrue(singleSegs.isEmpty, "Single point trajectory must return empty segments (>= 2 points required)")

        // 2. Continuous Trajectory (No Discontinuities)
        let continuousPoints = [
            TrajectoryPoint(latitude: 37.7741, longitude: -122.4191, timestamp: baseDate, horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7742, longitude: -122.4192, timestamp: baseDate.addingTimeInterval(30), horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7743, longitude: -122.4193, timestamp: baseDate.addingTimeInterval(60), horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7744, longitude: -122.4194, timestamp: baseDate.addingTimeInterval(90), horizontalAccuracy: 10.0)
        ]
        let continuousSegs = TrajectoryMath.segment(points: continuousPoints)
        assertTrue(continuousSegs.count == 1, "Continuous points should produce exactly 1 segment")
        assertTrue(continuousSegs[0].points.count == 4, "Segment should contain all 4 points")
        assertTrue(continuousSegs[0].startDate == baseDate, "startDate should match first point")
        assertTrue(continuousSegs[0].endDate == baseDate.addingTimeInterval(90), "endDate should match last point")
        assertTrue(continuousSegs[0].duration == 90.0, "duration should be 90 seconds")
        assertTrue(continuousSegs[0].distanceMeters > 0.0, "distanceMeters should be greater than 0")

        // 3. Discontinuity: Time Gap > 5 minutes (300s)
        let timeGapPoints = [
            // Segment 1 (2 points)
            TrajectoryPoint(latitude: 37.7741, longitude: -122.4191, timestamp: baseDate, horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7742, longitude: -122.4192, timestamp: baseDate.addingTimeInterval(30), horizontalAccuracy: 10.0),
            // Gap of 301 seconds (> 300s threshold)
            // Segment 2 (2 points)
            TrajectoryPoint(latitude: 37.7743, longitude: -122.4193, timestamp: baseDate.addingTimeInterval(331), horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7744, longitude: -122.4194, timestamp: baseDate.addingTimeInterval(360), horizontalAccuracy: 10.0)
        ]
        let timeGapSegs = TrajectoryMath.segment(points: timeGapPoints)
        assertTrue(timeGapSegs.count == 2, "301s time gap should split into 2 segments (actual: \(timeGapSegs.count))")
        assertTrue(timeGapSegs[0].points.count == 2, "First segment must have 2 points")
        assertTrue(timeGapSegs[1].points.count == 2, "Second segment must have 2 points")

        // 4. Discontinuity: Speed > 50 m/s (180 km/h)
        // Distance ~2,000m in 10s -> speed = 200 m/s (> 50 m/s)
        let speedPoints = [
            // Segment 1 (2 points)
            TrajectoryPoint(latitude: 37.7741, longitude: -122.4191, timestamp: baseDate, horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7742, longitude: -122.4192, timestamp: baseDate.addingTimeInterval(30), horizontalAccuracy: 10.0),
            // High speed jump (latitude jump ~0.02 deg is ~2.2 km in 10 seconds = 220 m/s)
            // Segment 2 (2 points)
            TrajectoryPoint(latitude: 37.7940, longitude: -122.4192, timestamp: baseDate.addingTimeInterval(40), horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7941, longitude: -122.4193, timestamp: baseDate.addingTimeInterval(70), horizontalAccuracy: 10.0)
        ]
        let speedSegs = TrajectoryMath.segment(points: speedPoints)
        assertTrue(speedSegs.count == 2, "Speed > 50 m/s should split into 2 segments (actual: \(speedSegs.count))")

        // 5. Discontinuity: Distance Jump > 10 km (even if time delta allows moderate speed)
        // SF to San Jose (~70km in 2000s = 35 m/s < 50 m/s, but dist > 10km)
        let distanceJumpPoints = [
            TrajectoryPoint(latitude: 37.7749, longitude: -122.4194, timestamp: baseDate, horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7750, longitude: -122.4195, timestamp: baseDate.addingTimeInterval(30), horizontalAccuracy: 10.0),
            // San Jose coordinate (~70km away) at 200s gap (dist > 10km)
            TrajectoryPoint(latitude: 37.3382, longitude: -121.8863, timestamp: baseDate.addingTimeInterval(230), horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.3383, longitude: -121.8864, timestamp: baseDate.addingTimeInterval(260), horizontalAccuracy: 10.0)
        ]
        let distSegs = TrajectoryMath.segment(points: distanceJumpPoints)
        assertTrue(distSegs.count == 2, "Distance jump > 10km should split into 2 segments (actual: \(distSegs.count))")

        // 6. Discontinuity: Nonpositive Time Delta (dt <= 0)
        let nonpositivePoints = [
            TrajectoryPoint(latitude: 37.7741, longitude: -122.4191, timestamp: baseDate, horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7742, longitude: -122.4192, timestamp: baseDate.addingTimeInterval(30), horizontalAccuracy: 10.0),
            // Duplicate timestamp or backwards timestamp (out-of-order resolved or duplicate dt=0)
            TrajectoryPoint(latitude: 37.7743, longitude: -122.4193, timestamp: baseDate.addingTimeInterval(30), horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7744, longitude: -122.4194, timestamp: baseDate.addingTimeInterval(60), horizontalAccuracy: 10.0)
        ]
        let nonpositiveSegs = TrajectoryMath.segment(points: nonpositivePoints)
        assertTrue(nonpositiveSegs.count == 2, "Nonpositive time delta (dt=0) should split into 2 segments")

        // 7. Dropping Singleton Points (Segment < 2 points)
        // 3 points: p1 -> p2 (continuous), p3 isolated after 10-minute gap
        let singletonPoints = [
            TrajectoryPoint(latitude: 37.7741, longitude: -122.4191, timestamp: baseDate, horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7742, longitude: -122.4192, timestamp: baseDate.addingTimeInterval(30), horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7743, longitude: -122.4193, timestamp: baseDate.addingTimeInterval(700), horizontalAccuracy: 10.0)
        ]
        let singletonSegs = TrajectoryMath.segment(points: singletonPoints)
        assertTrue(singletonSegs.count == 1, "Isolated 3rd point must be dropped as singleton, yielding 1 segment")
        assertTrue(singletonSegs[0].points.count == 2, "Resulting segment must have 2 points")

        // 8. Filtering Unusable Accuracy & Invalid Coordinates
        let mixedPoints = [
            TrajectoryPoint(latitude: 37.7741, longitude: -122.4191, timestamp: baseDate, horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7742, longitude: -122.4192, timestamp: baseDate.addingTimeInterval(30), horizontalAccuracy: 250.0), // Accuracy > 200m rejected
            TrajectoryPoint(latitude: Double.nan, longitude: -122.4193, timestamp: baseDate.addingTimeInterval(60), horizontalAccuracy: 10.0), // NaN rejected
            TrajectoryPoint(latitude: 100.0, longitude: -122.4193, timestamp: baseDate.addingTimeInterval(90), horizontalAccuracy: 10.0), // Out of range lat rejected
            TrajectoryPoint(latitude: 37.7743, longitude: -122.4193, timestamp: baseDate.addingTimeInterval(120), horizontalAccuracy: -1.0), // Negative accuracy rejected
            TrajectoryPoint(latitude: 37.7744, longitude: -122.4194, timestamp: baseDate.addingTimeInterval(150), horizontalAccuracy: 50.0)
        ]
        // Valid points remaining: p0 (t=0) and p5 (t=150s, dt=150s, dist ~50m -> continuous)
        let filteredSegs = TrajectoryMath.segment(points: mixedPoints)
        assertTrue(filteredSegs.count == 1, "Invalid/inaccurate points must be filtered before segmentation")
        assertTrue(filteredSegs[0].points.count == 2, "Filtered segment should retain the 2 valid points")

        // 9. Chronological Sorting of Unsorted Input
        let unsortedPoints = [
            TrajectoryPoint(latitude: 37.7743, longitude: -122.4193, timestamp: baseDate.addingTimeInterval(60), horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7741, longitude: -122.4191, timestamp: baseDate, horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7742, longitude: -122.4192, timestamp: baseDate.addingTimeInterval(30), horizontalAccuracy: 10.0)
        ]
        let sortedSegs = TrajectoryMath.segment(points: unsortedPoints)
        assertTrue(sortedSegs.count == 1, "Unsorted input points must be sorted chronologically and segmented")
        assertTrue(sortedSegs[0].points[0].timestamp == baseDate, "First point in segment must have earliest timestamp")
        assertTrue(sortedSegs[0].points[2].timestamp == baseDate.addingTimeInterval(60), "Last point must have latest timestamp")

        // 10. Deterministic Stable ID Generation
        let run1 = TrajectoryMath.segment(points: continuousPoints)
        let run2 = TrajectoryMath.segment(points: continuousPoints)
        assertTrue(run1.count == 1 && run2.count == 1, "Both segmentation runs should produce 1 segment")
        assertTrue(run1[0].id == run2[0].id, "Segment IDs must be completely deterministic across runs (ID: \(run1[0].id))")
        assertFalse(run1[0].id.isEmpty, "Segment ID must not be empty")

        // Distinct segments must have distinct IDs
        let twoSegs = TrajectoryMath.segment(points: timeGapPoints)
        assertTrue(twoSegs.count == 2, "Should have 2 segments")
        assertTrue(twoSegs[0].id != twoSegs[1].id, "Distinct segments must have distinct IDs")

        if failureCount > 0 {
            print("Task 2 Foundation Tests FAILED with \(failureCount) failures.")
            exit(1)
        } else {
            print("All Task 2 Foundation Tests Passed Successfully!")
        }
    }
}
