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
        print("Running Task 2 Foundation Tests...")

        // 1. Grid Bucketing - Empty List
        let emptyCells = HeatmapGridMath.computeDensityGrid(coordinates: [])
        assertTrue(emptyCells.isEmpty, "Empty coordinates must produce empty cells")

        // 2. Grid Bucketing - Single Point
        let singlePoint = [(latitude: 37.7749, longitude: -122.4194)]
        let singleCells = HeatmapGridMath.computeDensityGrid(coordinates: singlePoint, cellSizeDegrees: 0.001)
        assertTrue(singleCells.count == 1, "Single point must produce 1 cell")
        assertTrue(singleCells[0].count == 1, "Single cell count must be 1")
        assertTrue(singleCells[0].intensity == 1.0, "Single cell intensity must be 1.0")
        assertTrue(singleCells[0].minLat <= 37.7749 && singleCells[0].maxLat >= 37.7749, "Point lat must be within cell bounds")
        assertTrue(singleCells[0].minLon <= -122.4194 && singleCells[0].maxLon >= -122.4194, "Point lon must be within cell bounds")

        // 3. Multi-Point Aggregation & Intensity Scaling
        let multiPoints = [
            (latitude: 37.7741, longitude: -122.4191), // Cell A
            (latitude: 37.7742, longitude: -122.4192), // Cell A
            (latitude: 37.7743, longitude: -122.4193), // Cell A
            (latitude: 37.7800, longitude: -122.4100)  // Cell B
        ]
        let multiCells = HeatmapGridMath.computeDensityGrid(coordinates: multiPoints, cellSizeDegrees: 0.001)
        assertTrue(multiCells.count == 2, "Should aggregate into 2 distinct cells")

        let cellA = multiCells.first(where: { $0.count == 3 })
        let cellB = multiCells.first(where: { $0.count == 1 })
        assertTrue(cellA != nil, "Cell A with count 3 must exist")
        assertTrue(cellB != nil, "Cell B with count 1 must exist")
        assertTrue(cellA!.intensity == 1.0, "Max density cell must have intensity 1.0")
        assertTrue(abs(cellB!.intensity - (1.0 / 3.0)) < 0.0001, "Cell B intensity must be proportional (1/3)")

        // 4. Negative Coordinates (Southern / Western hemispheres)
        let southernWesternPoints = [
            (latitude: -33.8688, longitude: 151.2093), // Sydney
            (latitude: -33.8689, longitude: 151.2094), // Sydney same cell
            (latitude: -22.9068, longitude: -43.1729)  // Rio de Janeiro
        ]
        let swCells = HeatmapGridMath.computeDensityGrid(coordinates: southernWesternPoints, cellSizeDegrees: 0.001)
        assertTrue(swCells.count == 2, "Should aggregate into 2 cells for southern/western coords")
        for cell in swCells {
            assertTrue(cell.minLat < cell.maxLat, "minLat must be strictly less than maxLat for negative coords")
            assertTrue(cell.minLon < cell.maxLon, "minLon must be strictly less than maxLon for negative coords")
        }

        // 5. Boundary & Pole Edge Handling
        let poleAndBoundaryPoints = [
            (latitude: 90.0, longitude: 180.0),
            (latitude: -90.0, longitude: -180.0),
            (latitude: 0.0, longitude: 0.0)
        ]
        let boundaryCells = HeatmapGridMath.computeDensityGrid(coordinates: poleAndBoundaryPoints, cellSizeDegrees: 0.001)
        assertTrue(boundaryCells.count == 3, "Boundary coordinates must bucket cleanly")
        for cell in boundaryCells {
            assertTrue(cell.minLat >= -90.0 && cell.maxLat <= 90.0, "Latitude must stay within [-90, 90]")
            assertTrue(cell.minLon >= -180.0 && cell.maxLon <= 180.0, "Longitude must stay within [-180, 180]")
        }

        // 6. Invalid & Nonfinite Coordinate Filtering
        let mixedPoints = [
            (latitude: 37.7741, longitude: -122.4191),
            (latitude: 100.0, longitude: -122.4191), // Invalid lat
            (latitude: 37.7741, longitude: 200.0),   // Invalid lon
            (latitude: Double.nan, longitude: 0.0),   // NaN
            (latitude: 0.0, longitude: Double.infinity) // Inf
        ]
        let filteredCells = HeatmapGridMath.computeDensityGrid(coordinates: mixedPoints, cellSizeDegrees: 0.001)
        assertTrue(filteredCells.count == 1, "Invalid coordinates must be excluded from density grid")
        assertTrue(filteredCells[0].count == 1, "Only 1 valid coordinate should be counted")

        // 7. DST 23-Hour Day (Spring Forward)
        var calendar = Calendar(identifier: .gregorian)
        guard let tz = TimeZone(identifier: "America/New_York") else {
            fatalError("TimeZone America/New_York missing")
        }
        calendar.timeZone = tz

        var springComponents = DateComponents()
        springComponents.year = 2026
        springComponents.month = 3
        springComponents.day = 8
        springComponents.hour = 12
        let springDate = calendar.date(from: springComponents)!
        let springInterval = HeatmapGridMath.dayInterval(for: springDate, calendar: calendar)
        let springDuration = springInterval.end.timeIntervalSince(springInterval.start)
        assertTrue(springDuration == 82800, "DST spring forward day must be exactly 23 hours (82800s)")
        assertTrue(springInterval.contains(springDate), "Spring interval must contain test date")

        // 8. DST 25-Hour Day (Fall Back)
        var fallComponents = DateComponents()
        fallComponents.year = 2026
        fallComponents.month = 11
        fallComponents.day = 1
        fallComponents.hour = 12
        let fallDate = calendar.date(from: fallComponents)!
        let fallInterval = HeatmapGridMath.dayInterval(for: fallDate, calendar: calendar)
        let fallDuration = fallInterval.end.timeIntervalSince(fallInterval.start)
        assertTrue(fallDuration == 90000, "DST fall back day must be exactly 25 hours (90000s)")
        assertTrue(fallInterval.contains(fallDate), "Fall interval must contain test date")

        // 9. Day Navigation & Today/Future Guard
        let fixedNow = springDate // simulate 'now' as 2026-03-08 12:00:00
        let prevFromNow = HeatmapGridMath.previousDay(from: fixedNow, calendar: calendar)
        let nextFromPrev = HeatmapGridMath.nextDay(from: prevFromNow, calendar: calendar)

        assertTrue(calendar.isDate(prevFromNow, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: fixedNow)!), "previousDay must decrement by 1 day")
        assertTrue(calendar.isDate(nextFromPrev, inSameDayAs: fixedNow), "nextDay must return to original day")

        // canNavigateNext guard:
        // Yesterday -> can navigate next
        assertTrue(HeatmapGridMath.canNavigateNext(from: prevFromNow, calendar: calendar, now: fixedNow), "Can navigate next from yesterday")
        // Today -> CANNOT navigate next
        assertFalse(HeatmapGridMath.canNavigateNext(from: fixedNow, calendar: calendar, now: fixedNow), "Cannot navigate next when on today")
        // Tomorrow / Future -> CANNOT navigate next (future guard)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: fixedNow)!
        assertFalse(HeatmapGridMath.canNavigateNext(from: tomorrow, calendar: calendar, now: fixedNow), "Cannot navigate next from future day")

        if failureCount > 0 {
            print("Task 2 Foundation Tests FAILED with \(failureCount) failures.")
            exit(1)
        } else {
            print("All Task 2 Foundation Tests Passed Successfully!")
        }
    }
}
