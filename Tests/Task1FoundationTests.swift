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
        print("Running Task 1 Foundation Tests...")

        // 1. Coordinate & Accuracy Validation Tests (Finite & In-Bounds)
        assertTrue(HeatmapGridMath.isValid(latitude: 37.7749, longitude: -122.4194, horizontalAccuracy: 10.0), "Valid coordinates should pass")
        assertTrue(HeatmapGridMath.isValid(latitude: 0.0, longitude: 0.0, horizontalAccuracy: 0.0), "Zero coordinates should pass")
        assertTrue(HeatmapGridMath.isValid(latitude: -90.0, longitude: -180.0, horizontalAccuracy: 0.0), "Min boundary coordinates should pass")
        assertTrue(HeatmapGridMath.isValid(latitude: 90.0, longitude: 180.0, horizontalAccuracy: 100.0), "Max boundary coordinates should pass")

        // 2. Out of Bounds & Negative Accuracy Validation
        assertFalse(HeatmapGridMath.isValid(latitude: 90.0001, longitude: 0.0, horizontalAccuracy: 5.0), "Latitude > 90 must fail")
        assertFalse(HeatmapGridMath.isValid(latitude: -90.0001, longitude: 0.0, horizontalAccuracy: 5.0), "Latitude < -90 must fail")
        assertFalse(HeatmapGridMath.isValid(latitude: 0.0, longitude: 180.0001, horizontalAccuracy: 5.0), "Longitude > 180 must fail")
        assertFalse(HeatmapGridMath.isValid(latitude: 0.0, longitude: -180.0001, horizontalAccuracy: 5.0), "Longitude < -180 must fail")
        assertFalse(HeatmapGridMath.isValid(latitude: 37.7749, longitude: -122.4194, horizontalAccuracy: -0.001), "Negative accuracy must fail")

        // 3. Nonfinite & NaN Validation Tests (Constraint: Reject nonfinite accuracy/coordinates)
        assertFalse(HeatmapGridMath.isValid(latitude: Double.nan, longitude: 0.0, horizontalAccuracy: 5.0), "NaN latitude must fail")
        assertFalse(HeatmapGridMath.isValid(latitude: 0.0, longitude: Double.nan, horizontalAccuracy: 5.0), "NaN longitude must fail")
        assertFalse(HeatmapGridMath.isValid(latitude: 0.0, longitude: 0.0, horizontalAccuracy: Double.nan), "NaN accuracy must fail")
        assertFalse(HeatmapGridMath.isValid(latitude: Double.infinity, longitude: 0.0, horizontalAccuracy: 5.0), "+Inf latitude must fail")
        assertFalse(HeatmapGridMath.isValid(latitude: -Double.infinity, longitude: 0.0, horizontalAccuracy: 5.0), "-Inf latitude must fail")
        assertFalse(HeatmapGridMath.isValid(latitude: 0.0, longitude: Double.infinity, horizontalAccuracy: 5.0), "+Inf longitude must fail")
        assertFalse(HeatmapGridMath.isValid(latitude: 0.0, longitude: -Double.infinity, horizontalAccuracy: 5.0), "-Inf longitude must fail")
        assertFalse(HeatmapGridMath.isValid(latitude: 0.0, longitude: 0.0, horizontalAccuracy: Double.infinity), "+Inf accuracy must fail")
        assertFalse(HeatmapGridMath.isValid(latitude: 0.0, longitude: 0.0, horizontalAccuracy: -Double.infinity), "-Inf accuracy must fail")

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

        let interval = HeatmapGridMath.dayInterval(for: testDate, calendar: calendar)
        let startOfDay = calendar.startOfDay(for: testDate)
        guard let nextStartOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            fatalError("Failed to compute nextStartOfDay")
        }

        assertTrue(interval.start == startOfDay, "Interval start must match startOfDay")
        assertTrue(interval.end == nextStartOfDay, "Interval end must match next day startOfDay")
        assertTrue(interval.contains(testDate), "Interval must contain noon on same day")
        assertTrue(testDate >= interval.start && testDate < interval.end, "Half-open interval must contain noon on same day")
        assertFalse(nextStartOfDay >= interval.start && nextStartOfDay < interval.end, "Half-open [start, nextStart) must exclude nextStartOfDay")
        // Duration on DST spring forward day should be 23 hours = 82800 seconds
        let duration = interval.end.timeIntervalSince(interval.start)
        assertTrue(duration == 82800, "DST spring forward day must have 23 hours duration (82800s)")

        // 5. isToday Tests
        let now = Date()
        assertTrue(HeatmapGridMath.isToday(now, calendar: calendar, now: now), "now must be recognized as today")
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        assertFalse(HeatmapGridMath.isToday(yesterday, calendar: calendar, now: now), "yesterday must not be today")
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        assertFalse(HeatmapGridMath.isToday(tomorrow, calendar: calendar, now: now), "tomorrow must not be today")

        // 6. Density Grid Robustness with Nonfinite/Tiny Inputs
        let nonfiniteGrid = HeatmapGridMath.computeDensityGrid(
            coordinates: [(latitude: 37.77, longitude: -122.41)],
            cellSizeDegrees: Double.nan
        )
        assertTrue(nonfiniteGrid.isEmpty, "NaN cellSizeDegrees must return empty without crashing")

        let zeroGrid = HeatmapGridMath.computeDensityGrid(
            coordinates: [(latitude: 37.77, longitude: -122.41)],
            cellSizeDegrees: 0.0
        )
        assertTrue(zeroGrid.isEmpty, "Zero cellSizeDegrees must return empty without crashing")

        let negativeGrid = HeatmapGridMath.computeDensityGrid(
            coordinates: [(latitude: 37.77, longitude: -122.41)],
            cellSizeDegrees: -0.001
        )
        assertTrue(negativeGrid.isEmpty, "Negative cellSizeDegrees must return empty without crashing")

        if failureCount > 0 {
            print("Task 1 Foundation Tests FAILED with \(failureCount) failures.")
            exit(1)
        } else {
            print("All Task 1 Foundation Tests Passed Successfully!")
        }
    }
}
