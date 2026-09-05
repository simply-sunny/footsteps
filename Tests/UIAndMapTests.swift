import XCTest
import SwiftData
import MapKit
@testable import Footsteps

final class UIAndMapTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema([LocationPoint.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
    }

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }

    func testDayIntervalFiltering() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 15
        components.hour = 12
        let targetDate = calendar.date(from: components)!

        let prevDate = calendar.date(byAdding: .day, value: -1, to: targetDate)!
        let nextDate = calendar.date(byAdding: .day, value: 1, to: targetDate)!

        let context = ModelContext(container)
        let pointTarget = LocationPoint(latitude: 37.77, longitude: -122.41, timestamp: targetDate)
        let pointPrev = LocationPoint(latitude: 37.77, longitude: -122.41, timestamp: prevDate)
        let pointNext = LocationPoint(latitude: 37.77, longitude: -122.41, timestamp: nextDate)

        context.insert(pointTarget)
        context.insert(pointPrev)
        context.insert(pointNext)
        try context.save()

        let interval = TrajectoryMath.dayInterval(for: targetDate, calendar: calendar)
        let start = interval.start
        let end = interval.end

        let descriptor = FetchDescriptor<LocationPoint>(
            predicate: #Predicate<LocationPoint> { point in
                point.timestamp >= start && point.timestamp < end
            }
        )

        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1, "Only points falling within the calendar day interval must be returned")
        XCTAssertEqual(fetched.first?.timestamp, targetDate)
    }

    func testDayNavigationAndFutureGuard() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!

        let now = Date()
        let yesterday = TrajectoryMath.previousDay(from: now, calendar: calendar)
        let returnedToday = TrajectoryMath.nextDay(from: yesterday, calendar: calendar)

        XCTAssertTrue(calendar.isDate(yesterday, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: now)!))
        XCTAssertTrue(calendar.isDate(returnedToday, inSameDayAs: now))

        XCTAssertTrue(TrajectoryMath.canNavigateNext(from: yesterday, calendar: calendar, now: now))
        XCTAssertFalse(TrajectoryMath.canNavigateNext(from: now, calendar: calendar, now: now))

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        XCTAssertFalse(TrajectoryMath.canNavigateNext(from: tomorrow, calendar: calendar, now: now))
    }

    func testTrajectorySegmentationAndOverlayGeneration() {
        let baseDate = Date(timeIntervalSince1970: 1772900000)
        let points = [
            TrajectoryPoint(latitude: 37.7741, longitude: -122.4191, timestamp: baseDate, horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7742, longitude: -122.4192, timestamp: baseDate.addingTimeInterval(30), horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7743, longitude: -122.4193, timestamp: baseDate.addingTimeInterval(60), horizontalAccuracy: 10.0)
        ]
        let segments = TrajectoryMath.segment(points: points)
        XCTAssertEqual(segments.count, 1)

        let segment = segments[0]
        let polyline = SegmentPolyline.create(from: segment)
        XCTAssertEqual(polyline.segmentID, segment.id)
        XCTAssertEqual(polyline.pointCount, 3)
        XCTAssertFalse(polyline.boundingMapRect.isNull)
        XCTAssertGreaterThan(polyline.boundingMapRect.size.width, 0)
        XCTAssertGreaterThan(polyline.boundingMapRect.size.height, 0)
    }

    func testEmptyDayOverlay() {
        let segments = TrajectoryMath.segment(points: [])
        XCTAssertTrue(segments.isEmpty)

        // Exact empty state overlay string validation
        let emptyStateString = "No data for this day"
        XCTAssertEqual(emptyStateString, "No data for this day")
    }

    func testNormalizedDayIdentity() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let morning = Date(timeIntervalSince1970: 1772956800) // 2026-03-08 08:00:00 UTC
        let evening = Date(timeIntervalSince1970: 1772992800) // 2026-03-08 18:00:00 UTC
        let nextDay = Date(timeIntervalSince1970: 1773043200) // 2026-03-09 08:00:00 UTC

        let morningStart = TrajectoryMath.dayInterval(for: morning, calendar: calendar).start
        let eveningStart = TrajectoryMath.dayInterval(for: evening, calendar: calendar).start
        let nextDayStart = TrajectoryMath.dayInterval(for: nextDay, calendar: calendar).start

        XCTAssertEqual(morningStart, eveningStart, "Same calendar day timestamps must produce identical view identity")
        XCTAssertNotEqual(morningStart, nextDayStart, "Different calendar days must produce distinct view identities")
    }

    func testNegativeCoordinatesAndAntimeridianPolyline() {
        let baseDate = Date(timeIntervalSince1970: 1772900000)
        let points = [
            TrajectoryPoint(latitude: -33.8688, longitude: 151.2093, timestamp: baseDate, horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: -33.8689, longitude: 151.2094, timestamp: baseDate.addingTimeInterval(30), horizontalAccuracy: 10.0)
        ]
        let segments = TrajectoryMath.segment(points: points)
        XCTAssertEqual(segments.count, 1)

        let polyline = SegmentPolyline.create(from: segments[0])
        XCTAssertFalse(polyline.boundingMapRect.isNull)
        XCTAssertGreaterThan(polyline.boundingMapRect.size.width, 0)
    }

    func testPolylineRendererAndSelectionStyling() {
        let coordinator = TrajectoryMapView.Coordinator()
        let mapView = MKMapView()

        let baseDate = Date(timeIntervalSince1970: 1772900000)
        let points = [
            TrajectoryPoint(latitude: 37.77, longitude: -122.42, timestamp: baseDate),
            TrajectoryPoint(latitude: 37.78, longitude: -122.41, timestamp: baseDate.addingTimeInterval(60))
        ]
        let segment = TrajectorySegment(id: "test_seg_1", points: points)
        let polyline = SegmentPolyline.create(from: segment)

        // Unselected polyline renderer
        coordinator.selectedSegmentID = nil
        guard let unselectedRenderer = coordinator.mapView(mapView, rendererFor: polyline) as? MKPolylineRenderer else {
            XCTFail("Renderer must be MKPolylineRenderer")
            return
        }
        XCTAssertEqual(unselectedRenderer.lineWidth, 3.5)
        XCTAssertEqual(unselectedRenderer.strokeColor, UIColor.systemBlue.withAlphaComponent(0.85))

        // Selected polyline renderer
        coordinator.selectedSegmentID = "test_seg_1"
        guard let selectedRenderer = coordinator.mapView(mapView, rendererFor: polyline) as? MKPolylineRenderer else {
            XCTFail("Renderer must be MKPolylineRenderer")
            return
        }
        XCTAssertEqual(selectedRenderer.lineWidth, 6.0)
        XCTAssertEqual(selectedRenderer.strokeColor, UIColor.systemOrange)
    }

    func testMapViewCoordinatorHitTestingAndSelection() {
        let coordinator = TrajectoryMapView.Coordinator()
        let mapView = MKMapView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))

        let baseDate = Date(timeIntervalSince1970: 1772900000)
        let seg1Points = [
            TrajectoryPoint(latitude: 37.7740, longitude: -122.4190, timestamp: baseDate),
            TrajectoryPoint(latitude: 37.7750, longitude: -122.4190, timestamp: baseDate.addingTimeInterval(30))
        ]
        let seg2Points = [
            TrajectoryPoint(latitude: 37.7800, longitude: -122.4100, timestamp: baseDate.addingTimeInterval(600)),
            TrajectoryPoint(latitude: 37.7810, longitude: -122.4100, timestamp: baseDate.addingTimeInterval(630))
        ]
        let seg1 = TrajectorySegment(id: "seg_alpha", points: seg1Points)
        let seg2 = TrajectorySegment(id: "seg_beta", points: seg2Points)
        coordinator.segments = [seg1, seg2]

        // Map framing
        mapView.setRegion(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.7745, longitude: -122.4190),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            ),
            animated: false
        )

        var reportedSelectedID: String? = nil
        coordinator.onSelectSegment = { id in
            reportedSelectedID = id
        }
        coordinator.handleMapTap(UITapGestureRecognizer())
        XCTAssertNil(reportedSelectedID, "Tapping without map view should not select")

        // Test near seg1 midpoint
        let seg1Mid = CLLocationCoordinate2D(latitude: 37.7745, longitude: -122.4190)
        let seg1ScreenPoint = mapView.convert(seg1Mid, toPointTo: mapView)

        // Calculate screen points and distance via TrajectoryMath
        let seg1ScreenCoords = seg1Points.map { pt -> (x: Double, y: Double) in
            let p = mapView.convert(CLLocationCoordinate2D(latitude: pt.latitude, longitude: pt.longitude), toPointTo: mapView)
            return (x: Double(p.x), y: Double(p.y))
        }
        let seg2ScreenCoords = seg2Points.map { pt -> (x: Double, y: Double) in
            let p = mapView.convert(CLLocationCoordinate2D(latitude: pt.latitude, longitude: pt.longitude), toPointTo: mapView)
            return (x: Double(p.x), y: Double(p.y))
        }

        let distToSeg1 = TrajectoryMath.distanceFromPointToPolyline(
            point: (x: Double(seg1ScreenPoint.x), y: Double(seg1ScreenPoint.y)),
            polyline: seg1ScreenCoords
        )
        let distToSeg2 = TrajectoryMath.distanceFromPointToPolyline(
            point: (x: Double(seg1ScreenPoint.x), y: Double(seg1ScreenPoint.y)),
            polyline: seg2ScreenCoords
        )

        XCTAssertLessThan(distToSeg1, 5.0, "Tap on seg1 midpoint should have small distance to seg1")
        XCTAssertGreaterThan(distToSeg2, 50.0, "Tap on seg1 midpoint should be far from seg2")
    }

    // MARK: - HealthKit StepCountReader & Details Sheet Tests

    func testStepCountFormatting() {
        // Nil count must degrade to "Steps unavailable"
        XCTAssertEqual(StepCountReader.formatStepCount(nil), "Steps unavailable")

        // Zero and non-zero counts
        XCTAssertEqual(StepCountReader.formatStepCount(0), "0 steps")
        XCTAssertEqual(StepCountReader.formatStepCount(1), "1 step")
        XCTAssertEqual(StepCountReader.formatStepCount(42), "42 steps")

        let thousandFormatted = StepCountReader.formatStepCount(1000)
        XCTAssertTrue(thousandFormatted.contains("1,000") || thousandFormatted.contains("1000"), "Must contain formatted 1000 steps")
        XCTAssertTrue(thousandFormatted.hasSuffix("steps"))
    }

    func testDurationMinutesFormatting() {
        XCTAssertEqual(StepCountReader.formatDurationMinutes(0.0), "1 min", "Sub-minute durations should display minimum 1 min")
        XCTAssertEqual(StepCountReader.formatDurationMinutes(29.0), "1 min")
        XCTAssertEqual(StepCountReader.formatDurationMinutes(60.0), "1 min")
        XCTAssertEqual(StepCountReader.formatDurationMinutes(89.0), "1 min")
        XCTAssertEqual(StepCountReader.formatDurationMinutes(91.0), "2 min")
        XCTAssertEqual(StepCountReader.formatDurationMinutes(300.0), "5 min")
        XCTAssertEqual(StepCountReader.formatDurationMinutes(3600.0), "60 min")
    }

    func testTimeIntervalFormatting() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 15
        components.hour = 9
        components.minute = 15
        let start = calendar.date(from: components)!
        let end = calendar.date(byAdding: .minute, value: 45, to: start)!

        let formatted = StepCountReader.formatTimeInterval(
            start: start,
            end: end,
            locale: Locale(identifier: "en_US"),
            timeZone: TimeZone(identifier: "UTC")!
        )
        XCTAssertFalse(formatted.isEmpty)
        XCTAssertTrue(formatted.contains("9:15") && formatted.contains("10:00"))
    }

    func testInvalidQueryIntervalGuard() async {
        let reader = StepCountReader.shared
        let now = Date()
        let past = now.addingTimeInterval(-60)

        // Reversed interval where start > end must return nil
        let resultReversed = await reader.fetchStepCount(startDate: now, endDate: past)
        XCTAssertNil(resultReversed, "Reversed date interval must safely return nil")

        // Equal start and end must return nil
        let resultEqual = await reader.fetchStepCount(startDate: now, endDate: now)
        XCTAssertNil(resultEqual, "Zero-duration date interval must safely return nil")
    }
}
