import XCTest
import CoreLocation
@testable import Footsteps

final class DayHistoryTests: XCTestCase {

    // Helper to construct a calendar with specific time zone
    private func makeCalendar(timeZoneIdentifier: String = "UTC") -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return cal
    }

    // Helper to create test points
    private func makePoint(lat: Double, lon: Double, time: Date, acc: Double = 5.0) -> TrajectoryPoint {
        TrajectoryPoint(latitude: lat, longitude: lon, timestamp: time, horizontalAccuracy: acc)
    }

    // MARK: - 1. Empty Day Test
    func testEmptyDayAllElapsedIsUnknown() {
        let cal = makeCalendar()
        let day = cal.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let now = day.addingTimeInterval(86400 * 2) // Querying a past day

        let history = DayHistory.build(points: [], selectedDate: day, now: now, calendar: cal)

        XCTAssertEqual(history.observedDistanceMeters, 0.0)
        XCTAssertEqual(history.places.count, 0)
        XCTAssertEqual(history.stays.count, 0)
        XCTAssertEqual(history.movingDuration, 0.0)
        XCTAssertEqual(history.stationaryDuration, 0.0)
        XCTAssertEqual(history.totalElapsedDuration, 86400.0)
        XCTAssertEqual(history.unknownDuration, 86400.0)
        XCTAssertEqual(history.movingDuration + history.stationaryDuration + history.unknownDuration, history.totalElapsedDuration, accuracy: 0.001)
    }

    // MARK: - 2. Singleton Observation (No Stay Duration Inferred)
    func testSingletonHasNoStayDuration() {
        let cal = makeCalendar()
        let day = cal.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let singleTime = day.addingTimeInterval(3600) // 1:00 AM
        let pt = makePoint(lat: 37.7749, lon: -122.4194, time: singleTime)
        let now = day.addingTimeInterval(86400 * 2)

        let history = DayHistory.build(points: [pt], selectedDate: day, now: now, calendar: cal)

        XCTAssertEqual(history.observedDistanceMeters, 0.0)
        XCTAssertEqual(history.stays.count, 0, "A single observation is not a stay")
        XCTAssertEqual(history.singleObservations.count, 1)
        XCTAssertEqual(history.stationaryDuration, 0.0)
        XCTAssertEqual(history.movingDuration, 0.0)
        XCTAssertEqual(history.totalElapsedDuration, 86400.0)
        XCTAssertEqual(history.unknownDuration, 86400.0)
        XCTAssertEqual(history.movingDuration + history.stationaryDuration + history.unknownDuration, history.totalElapsedDuration, accuracy: 0.001)
    }

    // MARK: - 3. Mixed Walk - Stay - Walk
    func testMixedWalkStayWalkPartition() {
        let cal = makeCalendar()
        let day = cal.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let now = day.addingTimeInterval(86400 * 2)

        var points: [TrajectoryPoint] = []
        // Walk 1: 10:00 to 10:10 (600s, 10 fixes 60s apart is a gap, so let's do 1Hz or 5s fixes)
        // 5s fixes for 600s = 121 fixes
        let t = day.addingTimeInterval(36000) // 10:00:00
        for i in 0...120 {
            let curTime = t.addingTimeInterval(Double(i * 5))
            let lat = 37.7749 + Double(i) * 0.0001
            points.append(makePoint(lat: lat, lon: -122.4194, time: curTime))
        }

        // Stay 1 at end of Walk 1: 10:10 to 10:40 (1800s dwell)
        let stayStart = t.addingTimeInterval(600)
        let stayLat = 37.7749 + 120.0 * 0.0001
        for i in 1...180 { // every 10s for 1800s
            let curTime = stayStart.addingTimeInterval(Double(i * 10))
            points.append(makePoint(lat: stayLat, lon: -122.4194, time: curTime))
        }

        // Walk 2: 10:40 to 10:50 (600s)
        let walk2Start = stayStart.addingTimeInterval(1800)
        for i in 1...120 {
            let curTime = walk2Start.addingTimeInterval(Double(i * 5))
            let lat = stayLat + Double(i) * 0.0001
            points.append(makePoint(lat: lat, lon: -122.4194, time: curTime))
        }

        let history = DayHistory.build(points: points, selectedDate: day, now: now, calendar: cal)

        XCTAssertEqual(history.stays.count, 1)
        XCTAssertGreaterThan(history.observedDistanceMeters, 500.0)
        XCTAssertEqual(history.places.count, 1)

        // Verify time partition sum exactly matches day elapsed
        XCTAssertEqual(history.totalElapsedDuration, 86400.0)
        XCTAssertGreaterThan(history.movingDuration, 0)
        XCTAssertGreaterThan(history.stationaryDuration, 0)
        XCTAssertGreaterThan(history.unknownDuration, 0)
        let sum = history.movingDuration + history.stationaryDuration + history.unknownDuration
        XCTAssertEqual(sum, history.totalElapsedDuration, accuracy: 0.001)
    }

    // MARK: - 4. Missing Intervals (40s, 120s, 299s) and Gaps
    func testGapsAreClassifiedAsUnknownAndDoNotInferDistance() {
        let cal = makeCalendar()
        let day = cal.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let now = day.addingTimeInterval(86400 * 2)

        // Fix at 10:00
        let p1 = makePoint(lat: 37.7749, lon: -122.4194, time: day.addingTimeInterval(36000))
        // Gap of 120s -> Fix at 10:02:00
        let p2 = makePoint(lat: 37.7750, lon: -122.4195, time: day.addingTimeInterval(36120))
        // Gap of 299s -> Fix at 10:06:59
        let p3 = makePoint(lat: 37.7751, lon: -122.4196, time: day.addingTimeInterval(36419))

        let history = DayHistory.build(points: [p1, p2, p3], selectedDate: day, now: now, calendar: cal)

        XCTAssertEqual(history.observedDistanceMeters, 0.0, "Disconnected points across >30s gaps must not create moving distance")
        XCTAssertEqual(history.movingDuration, 0.0)
        XCTAssertEqual(history.stationaryDuration, 0.0)
        XCTAssertEqual(history.unknownDuration, 86400.0)
        XCTAssertEqual(history.movingDuration + history.stationaryDuration + history.unknownDuration, history.totalElapsedDuration, accuracy: 0.001)
    }

    // MARK: - 5. Poor Fix Barrier (>200m) Splits Intervals
    func testPoorFixBarriersAreUnknownAndSplitSegments() {
        let cal = makeCalendar()
        let day = cal.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let now = day.addingTimeInterval(86400 * 2)

        // 3 continuous 1Hz points
        let p1 = makePoint(lat: 37.7749, lon: -122.4194, time: day.addingTimeInterval(36000), acc: 5.0)
        let p2 = makePoint(lat: 37.7750, lon: -122.4194, time: day.addingTimeInterval(36005), acc: 5.0)
        // Poor fix (>200m)
        let pBad = makePoint(lat: 37.7751, lon: -122.4194, time: day.addingTimeInterval(36010), acc: 350.0)
        // 2 more continuous points
        let p3 = makePoint(lat: 37.7752, lon: -122.4194, time: day.addingTimeInterval(36015), acc: 5.0)
        let p4 = makePoint(lat: 37.7753, lon: -122.4194, time: day.addingTimeInterval(36020), acc: 5.0)

        let history = DayHistory.build(points: [p1, p2, pBad, p3, p4], selectedDate: day, now: now, calendar: cal)

        XCTAssertEqual(history.movingSegments.count, 2, "Poor fix must split into 2 separate moving segments")
        let sum = history.movingDuration + history.stationaryDuration + history.unknownDuration
        XCTAssertEqual(sum, history.totalElapsedDuration, accuracy: 0.001)
    }

    // MARK: - 6. DST Spring (23 hours) & DST Fall (25 hours)
    func testDSTSpringAndFallElapsedDuration() {
        // America/New_York DST transitions
        let cal = makeCalendar(timeZoneIdentifier: "America/New_York")

        // 2026 Spring Forward: March 8, 2026 (23 hours = 82,800s)
        let springDay = cal.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let nowSpring = springDay.addingTimeInterval(86400 * 5)
        let historySpring = DayHistory.build(points: [], selectedDate: springDay, now: nowSpring, calendar: cal)
        XCTAssertEqual(historySpring.totalElapsedDuration, 82800.0, "Spring forward day must have 23 hours elapsed")
        XCTAssertEqual(historySpring.unknownDuration, 82800.0)

        // 2026 Fall Back: November 1, 2026 (25 hours = 90,000s)
        let fallDay = cal.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let nowFall = fallDay.addingTimeInterval(86400 * 5)
        let historyFall = DayHistory.build(points: [], selectedDate: fallDay, now: nowFall, calendar: cal)
        XCTAssertEqual(historyFall.totalElapsedDuration, 90000.0, "Fall back day must have 25 hours elapsed")
        XCTAssertEqual(historyFall.unknownDuration, 90000.0)
    }

    // MARK: - 7. Today Clamped to Now and Rejects Future Samples
    func testTodayElapsedClampedToNowAndFiltersFutureSamples() {
        let cal = makeCalendar()
        let today = cal.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let now = today.addingTimeInterval(3600 * 14) // 2:00 PM today (14 hours elapsed = 50,400s)

        // Point at 10:00 AM (valid)
        let pValid = makePoint(lat: 37.7749, lon: -122.4194, time: today.addingTimeInterval(36000))
        // Point at 4:00 PM (future sample, invalid)
        let pFuture = makePoint(lat: 37.7750, lon: -122.4195, time: today.addingTimeInterval(3600 * 16))

        let history = DayHistory.build(points: [pValid, pFuture], selectedDate: today, now: now, calendar: cal)

        XCTAssertEqual(history.totalElapsedDuration, 50400.0, "Today elapsed must be clamped to now")
        XCTAssertEqual(history.singleObservations.count, 1, "Future points must be filtered")
        let sum = history.movingDuration + history.stationaryDuration + history.unknownDuration
        XCTAssertEqual(sum, history.totalElapsedDuration, accuracy: 0.001)

        // Future day test
        let futureDay = today.addingTimeInterval(86400)
        let historyFuture = DayHistory.build(points: [], selectedDate: futureDay, now: now, calendar: cal)
        XCTAssertEqual(historyFuture.totalElapsedDuration, 0.0, "Future day elapsed must be 0")
        XCTAssertEqual(historyFuture.unknownDuration, 0.0)
    }

    // MARK: - 8. Repeated Stays Group Into Same Place Without Bridging Time
    func testRepeatedStaysGroupWithoutBridgingMissingTime() {
        let cal = makeCalendar()
        let day = cal.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let now = day.addingTimeInterval(86400 * 2)

        // Stay 1 at Home (37.7749, -122.4194): 8:00 to 9:00 (3600s)
        var points: [TrajectoryPoint] = []
        let homeStart = day.addingTimeInterval(8 * 3600)
        for i in 0...360 { // every 10s
            points.append(makePoint(lat: 37.7749, lon: -122.4194, time: homeStart.addingTimeInterval(Double(i * 10))))
        }

        // Gap / Travel away from 9:00 to 17:00 (unobserved)

        // Stay 2 at Home (37.77492, -122.41941, within 5m): 17:00 to 20:00 (10800s)
        let home2Start = day.addingTimeInterval(17 * 3600)
        for i in 0...1080 { // every 10s
            points.append(makePoint(lat: 37.77492, lon: -122.41941, time: home2Start.addingTimeInterval(Double(i * 10))))
        }

        let history = DayHistory.build(points: points, selectedDate: day, now: now, calendar: cal)

        XCTAssertEqual(history.stays.count, 2, "There are 2 distinct stay episodes")
        XCTAssertEqual(history.places.count, 1, "Both stays must be grouped into 1 conservative place")
        XCTAssertEqual(history.places.first?.visitCount, 2)
        XCTAssertEqual(history.places.first?.totalDuration ?? 0, 3600 + 10800, accuracy: 1.0)

        // Verify the 8-hour gap between 9:00 and 17:00 is STILL unknown duration!
        XCTAssertEqual(history.stationaryDuration, 3600 + 10800, accuracy: 1.0)
        let sum = history.movingDuration + history.stationaryDuration + history.unknownDuration
        XCTAssertEqual(sum, history.totalElapsedDuration, accuracy: 0.001)
    }

    // MARK: - 9. Stay Duration Weighting is Invariant to Sample Rate
    func testStayDurationWeightingInvariantToSampleRate() {
        let cal = makeCalendar()
        let day = cal.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let now = day.addingTimeInterval(86400 * 2)

        // Case A: 100 fixes over 1000s (every 10s)
        var pointsA: [TrajectoryPoint] = []
        let startA = day.addingTimeInterval(3600)
        for i in 0...100 {
            pointsA.append(makePoint(lat: 37.7749, lon: -122.4194, time: startA.addingTimeInterval(Double(i * 10))))
        }
        let historyA = DayHistory.build(points: pointsA, selectedDate: day, now: now, calendar: cal)

        // Case B: 1000 fixes over 1000s (every 1s)
        var pointsB: [TrajectoryPoint] = []
        let startB = day.addingTimeInterval(3600)
        for i in 0...1000 {
            pointsB.append(makePoint(lat: 37.7749, lon: -122.4194, time: startB.addingTimeInterval(Double(i))))
        }
        let historyB = DayHistory.build(points: pointsB, selectedDate: day, now: now, calendar: cal)

        XCTAssertEqual(historyA.stays.count, 1)
        XCTAssertEqual(historyB.stays.count, 1)
        XCTAssertEqual(historyA.stays[0].duration, historyB.stays[0].duration, accuracy: 1.0, "Stay duration must be identical regardless of 100 fixes vs 1000 fixes")
        XCTAssertEqual(historyA.stationaryDuration, historyB.stationaryDuration, accuracy: 1.0)
    }

    // MARK: - 10. Cumulative Distance Disjoint Series
    func testCumulativeDistanceBreaksAcrossGaps() {
        let cal = makeCalendar()
        let day = cal.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let now = day.addingTimeInterval(86400 * 2)

        // Walk 1 (10:00:00 to 10:00:20, 5 fixes 5s apart)
        var points: [TrajectoryPoint] = []
        let t1 = day.addingTimeInterval(36000)
        for i in 0...4 {
            points.append(makePoint(lat: 37.7749 + Double(i) * 0.0001, lon: -122.4194, time: t1.addingTimeInterval(Double(i * 5))))
        }

        // Gap of 1 hour

        // Walk 2 (11:00:00 to 11:00:20, 5 fixes 5s apart)
        let t2 = day.addingTimeInterval(39600)
        for i in 0...4 {
            points.append(makePoint(lat: 37.7760 + Double(i) * 0.0001, lon: -122.4194, time: t2.addingTimeInterval(Double(i * 5))))
        }

        let history = DayHistory.build(points: points, selectedDate: day, now: now, calendar: cal)

        XCTAssertEqual(history.movingSegments.count, 2)
        XCTAssertEqual(history.cumulativeDistanceSeries.count, 2, "Cumulative distance series must be broken into 2 disjoint series across unknown gap")
        XCTAssertGreaterThan(history.cumulativeDistanceSeries[0].last?.distanceMeters ?? 0, 0)
        // Series 2 continues from cumulative total of series 1
        let endDist1 = history.cumulativeDistanceSeries[0].last?.distanceMeters ?? 0
        let startDist2 = history.cumulativeDistanceSeries[1].first?.distanceMeters ?? 0
        XCTAssertEqual(startDist2, endDist1, accuracy: 0.001)
    }
}
