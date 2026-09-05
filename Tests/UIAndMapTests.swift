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

        let interval = HeatmapGridMath.dayInterval(for: targetDate, calendar: calendar)
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
        let yesterday = HeatmapGridMath.previousDay(from: now, calendar: calendar)
        let returnedToday = HeatmapGridMath.nextDay(from: yesterday, calendar: calendar)

        XCTAssertTrue(calendar.isDate(yesterday, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: now)!))
        XCTAssertTrue(calendar.isDate(returnedToday, inSameDayAs: now))

        XCTAssertTrue(HeatmapGridMath.canNavigateNext(from: yesterday, calendar: calendar, now: now))
        XCTAssertFalse(HeatmapGridMath.canNavigateNext(from: now, calendar: calendar, now: now))

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        XCTAssertFalse(HeatmapGridMath.canNavigateNext(from: tomorrow, calendar: calendar, now: now))
    }

    func testDensityGridAndOverlayGeneration() {
        let points = [
            LocationPoint(latitude: 37.7741, longitude: -122.4191),
            LocationPoint(latitude: 37.7742, longitude: -122.4192),
            LocationPoint(latitude: 37.7800, longitude: -122.4100)
        ]
        let coords = points.map { (latitude: $0.latitude, longitude: $0.longitude) }
        let cells = HeatmapGridMath.computeDensityGrid(coordinates: coords, cellSizeDegrees: 0.001)

        XCTAssertEqual(cells.count, 2)
        let maxDensity = cells.first(where: { $0.count == 2 })
        XCTAssertNotNil(maxDensity)
        XCTAssertEqual(maxDensity?.intensity, 1.0)

        let overlay = HeatmapOverlay(cells: cells)
        XCTAssertFalse(overlay.boundingMapRect.isNull)
        XCTAssertGreaterThan(overlay.boundingMapRect.size.width, 0)
        XCTAssertGreaterThan(overlay.boundingMapRect.size.height, 0)
        XCTAssertEqual(overlay.cells.count, 2)
    }

    func testEmptyDayOverlay() {
        let overlay = HeatmapOverlay(cells: [])
        XCTAssertTrue(overlay.boundingMapRect.isNull)
        XCTAssertTrue(overlay.cells.isEmpty)
    }

    func testNegativeCoordinatesAndAntimeridianOverlay() {
        let coords = [
            (latitude: -33.8688, longitude: 151.2093),
            (latitude: -22.9068, longitude: -43.1729),
            (latitude: 0.0, longitude: 180.0)
        ]
        let cells = HeatmapGridMath.computeDensityGrid(coordinates: coords, cellSizeDegrees: 0.001)
        XCTAssertEqual(cells.count, 3)

        let overlay = HeatmapOverlay(cells: cells)
        XCTAssertFalse(overlay.boundingMapRect.isNull)
        XCTAssertGreaterThan(overlay.boundingMapRect.size.width, 0)
    }

    func testDensityPolygonRendererAlpha() {
        let coordinator = HeatmapMapView.Coordinator()
        let mapView = MKMapView()

        var coords = [
            CLLocationCoordinate2D(latitude: 37.77, longitude: -122.41),
            CLLocationCoordinate2D(latitude: 37.78, longitude: -122.41),
            CLLocationCoordinate2D(latitude: 37.78, longitude: -122.40),
            CLLocationCoordinate2D(latitude: 37.77, longitude: -122.40)
        ]
        let polygon = DensityPolygon(coordinates: &coords, count: 4)
        polygon.intensity = 0.5

        let renderer = coordinator.mapView(mapView, rendererFor: polygon)
        XCTAssertTrue(renderer is MKPolygonRenderer)
    }
}
