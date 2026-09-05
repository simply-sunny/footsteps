import Foundation

@main
struct Task1FoundationTests {
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
        print("Running Task 1 Foundation Tests (Validation, Calendar Math, Haversine, 2D Hit Testing)...")

        // 1. Coordinate & Accuracy Validation Tests (Finite & In-Bounds)
        assertTrue(TrajectoryMath.isValid(latitude: 37.7749, longitude: -122.4194, horizontalAccuracy: 10.0), "Valid coordinates should pass")
        assertTrue(TrajectoryMath.isValid(latitude: 0.0, longitude: 0.0, horizontalAccuracy: 0.0), "Zero coordinates should pass")
        assertTrue(TrajectoryMath.isValid(latitude: -90.0, longitude: -180.0, horizontalAccuracy: 0.0), "Min boundary coordinates should pass")
        assertTrue(TrajectoryMath.isValid(latitude: 90.0, longitude: 180.0, horizontalAccuracy: 100.0), "Max boundary coordinates should pass")
        assertTrue(TrajectoryMath.isValid(latitude: 37.7749, longitude: -122.4194, horizontalAccuracy: 200.0), "200m horizontalAccuracy should pass with default threshold")

        // 2. Out of Bounds, Negative Accuracy, and Accuracy Threshold Exceeded
        assertFalse(TrajectoryMath.isValid(latitude: 90.0001, longitude: 0.0, horizontalAccuracy: 5.0), "Latitude > 90 must fail")
        assertFalse(TrajectoryMath.isValid(latitude: -90.0001, longitude: 0.0, horizontalAccuracy: 5.0), "Latitude < -90 must fail")
        assertFalse(TrajectoryMath.isValid(latitude: 0.0, longitude: 180.0001, horizontalAccuracy: 5.0), "Longitude > 180 must fail")
        assertFalse(TrajectoryMath.isValid(latitude: 0.0, longitude: -180.0001, horizontalAccuracy: 5.0), "Longitude < -180 must fail")
        assertFalse(TrajectoryMath.isValid(latitude: 37.7749, longitude: -122.4194, horizontalAccuracy: -0.001), "Negative accuracy must fail")
        assertFalse(TrajectoryMath.isValid(latitude: 37.7749, longitude: -122.4194, horizontalAccuracy: 200.001), "Accuracy > 200m must fail with default threshold")
        assertFalse(TrajectoryMath.isValid(latitude: 37.7749, longitude: -122.4194, horizontalAccuracy: 500.0), "Coarse 500m accuracy must fail")

        // 3. Nonfinite & NaN Validation Tests
        assertFalse(TrajectoryMath.isValid(latitude: Double.nan, longitude: 0.0, horizontalAccuracy: 5.0), "NaN latitude must fail")
        assertFalse(TrajectoryMath.isValid(latitude: 0.0, longitude: Double.nan, horizontalAccuracy: 5.0), "NaN longitude must fail")
        assertFalse(TrajectoryMath.isValid(latitude: 0.0, longitude: 0.0, horizontalAccuracy: Double.nan), "NaN accuracy must fail")
        assertFalse(TrajectoryMath.isValid(latitude: Double.infinity, longitude: 0.0, horizontalAccuracy: 5.0), "+Inf latitude must fail")
        assertFalse(TrajectoryMath.isValid(latitude: -Double.infinity, longitude: 0.0, horizontalAccuracy: 5.0), "-Inf latitude must fail")
        assertFalse(TrajectoryMath.isValid(latitude: 0.0, longitude: Double.infinity, horizontalAccuracy: 5.0), "+Inf longitude must fail")
        assertFalse(TrajectoryMath.isValid(latitude: 0.0, longitude: -Double.infinity, horizontalAccuracy: 5.0), "-Inf longitude must fail")
        assertFalse(TrajectoryMath.isValid(latitude: 0.0, longitude: 0.0, horizontalAccuracy: Double.infinity), "+Inf accuracy must fail")
        assertFalse(TrajectoryMath.isValid(latitude: 0.0, longitude: 0.0, horizontalAccuracy: -Double.infinity), "-Inf accuracy must fail")

        // 4. DST-Aware Date Interval Tests
        var calendar = Calendar(identifier: .gregorian)
        guard let tz = TimeZone(identifier: "America/New_York") else {
            fatalError("TimeZone America/New_York missing")
        }
        calendar.timeZone = tz
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 8 // US DST transition day in 2026 (spring forward 23h day)
        components.hour = 12
        guard let testDate = calendar.date(from: components) else {
            fatalError("Failed to build testDate")
        }

        let interval = TrajectoryMath.dayInterval(for: testDate, calendar: calendar)
        let startOfDay = calendar.startOfDay(for: testDate)
        guard let nextStartOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            fatalError("Failed to compute nextStartOfDay")
        }

        assertTrue(interval.start == startOfDay, "Interval start must match startOfDay")
        assertTrue(interval.end == nextStartOfDay, "Interval end must match next day startOfDay")
        assertTrue(interval.contains(testDate), "Interval must contain noon on same day")
        assertTrue(testDate >= interval.start && testDate < interval.end, "Half-open interval must contain noon on same day")
        assertFalse(nextStartOfDay >= interval.start && nextStartOfDay < interval.end, "Half-open [start, nextStart) must exclude nextStartOfDay")
        let duration = interval.end.timeIntervalSince(interval.start)
        assertTrue(duration == 82800, "DST spring forward day must have 23 hours duration (82800s)")

        // 5. isToday & Navigation Tests
        let now = Date()
        assertTrue(TrajectoryMath.isToday(now, calendar: calendar, now: now), "now must be recognized as today")
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        assertFalse(TrajectoryMath.isToday(yesterday, calendar: calendar, now: now), "yesterday must not be today")
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        assertFalse(TrajectoryMath.isToday(tomorrow, calendar: calendar, now: now), "tomorrow must not be today")

        assertTrue(TrajectoryMath.canNavigateNext(from: yesterday, calendar: calendar, now: now), "canNavigateNext from yesterday must be true")
        assertFalse(TrajectoryMath.canNavigateNext(from: now, calendar: calendar, now: now), "canNavigateNext from today must be false")
        assertFalse(TrajectoryMath.canNavigateNext(from: tomorrow, calendar: calendar, now: now), "canNavigateNext from tomorrow must be false")

        let prev = TrajectoryMath.previousDay(from: now, calendar: calendar)
        let backToToday = TrajectoryMath.nextDay(from: prev, calendar: calendar)
        assertTrue(calendar.isDate(prev, inSameDayAs: yesterday), "previousDay must decrement by 1 day")
        assertTrue(calendar.isDate(backToToday, inSameDayAs: now), "nextDay must increment by 1 day")

        // 6. Haversine Distance Tests
        let zeroDist = TrajectoryMath.haversineDistance(lat1: 37.7749, lon1: -122.4194, lat2: 37.7749, lon2: -122.4194)
        assertTrue(zeroDist == 0.0, "Distance between identical coordinates must be 0.0")

        // San Francisco (37.7749, -122.4194) to New York (40.7128, -74.0060) is ~4,130 km
        let sfNyDist = TrajectoryMath.haversineDistance(lat1: 37.7749, lon1: -122.4194, lat2: 40.7128, lon2: -74.0060)
        assertTrue(sfNyDist > 4_100_000 && sfNyDist < 4_200_000, "SF to NY distance should be ~4,130 km (actual: \(sfNyDist)m)")

        // 1 degree latitude at equator is ~111.19 km
        let oneDegreeEq = TrajectoryMath.haversineDistance(lat1: 0.0, lon1: 0.0, lat2: 1.0, lon2: 0.0)
        assertTrue(abs(oneDegreeEq - 111_195) < 500, "1 degree latitude at equator should be ~111.2 km (actual: \(oneDegreeEq)m)")

        // 7. 2D Hit Testing Math Tests (Point to Line Segment & Polyline)
        // Segment from (0, 0) to (10, 0)
        let segStart = (x: 0.0, y: 0.0)
        let segEnd = (x: 10.0, y: 0.0)

        // Point directly on segment
        let dOnSeg = TrajectoryMath.distanceFromPointToLineSegment(point: (x: 5.0, y: 0.0), lineStart: segStart, lineEnd: segEnd)
        assertTrue(abs(dOnSeg) < 1e-9, "Point on segment must have distance 0")

        // Point perpendicular above midpoint (5, 4)
        let dPerp = TrajectoryMath.distanceFromPointToLineSegment(point: (x: 5.0, y: 4.0), lineStart: segStart, lineEnd: segEnd)
        assertTrue(abs(dPerp - 4.0) < 1e-9, "Perpendicular distance must be 4.0 (actual: \(dPerp))")

        // Point beyond segment start (-3, 4) -> nearest is (0, 0), distance = 5
        let dBeyondStart = TrajectoryMath.distanceFromPointToLineSegment(point: (x: -3.0, y: 4.0), lineStart: segStart, lineEnd: segEnd)
        assertTrue(abs(dBeyondStart - 5.0) < 1e-9, "Distance beyond start clamped to start endpoint must be 5.0")

        // Point beyond segment end (13, 4) -> nearest is (10, 0), distance = 5
        let dBeyondEnd = TrajectoryMath.distanceFromPointToLineSegment(point: (x: 13.0, y: 4.0), lineStart: segStart, lineEnd: segEnd)
        assertTrue(abs(dBeyondEnd - 5.0) < 1e-9, "Distance beyond end clamped to end endpoint must be 5.0")

        // Polyline: [(0,0), (10,0), (10,10)]
        let polyline = [(x: 0.0, y: 0.0), (x: 10.0, y: 0.0), (x: 10.0, y: 10.0)]
        let dPoly1 = TrajectoryMath.distanceFromPointToPolyline(point: (x: 5.0, y: 2.0), polyline: polyline)
        assertTrue(abs(dPoly1 - 2.0) < 1e-9, "Polyline distance near segment 1 must be 2.0")
        let dPoly2 = TrajectoryMath.distanceFromPointToPolyline(point: (x: 12.0, y: 5.0), polyline: polyline)
        assertTrue(abs(dPoly2 - 2.0) < 1e-9, "Polyline distance near segment 2 must be 2.0")

        if failureCount > 0 {
            print("Task 1 Foundation Tests FAILED with \(failureCount) failures.")
            exit(1)
        } else {
            print("All Task 1 Foundation Tests Passed Successfully!")
        }
    }
}
