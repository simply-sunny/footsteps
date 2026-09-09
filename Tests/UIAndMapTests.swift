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
            TrajectoryPoint(latitude: 37.7743, longitude: -122.4193, timestamp: baseDate.addingTimeInterval(30), horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7745, longitude: -122.4195, timestamp: baseDate.addingTimeInterval(60), horizontalAccuracy: 10.0)
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

        let emptyStateString = "No data for this day."
        XCTAssertEqual(emptyStateString, "No data for this day.")
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
            TrajectoryPoint(latitude: -33.8690, longitude: 151.2095, timestamp: baseDate.addingTimeInterval(30), horizontalAccuracy: 10.0)
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

        coordinator.selectedSegmentID = nil
        guard let unselectedRenderer = coordinator.mapView(mapView, rendererFor: polyline) as? MKPolylineRenderer else {
            XCTFail("Renderer must be MKPolylineRenderer")
            return
        }
        XCTAssertEqual(unselectedRenderer.lineWidth, 3.5)
        XCTAssertEqual(unselectedRenderer.strokeColor, UIColor.systemBlue.withAlphaComponent(0.85))

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

        let seg1Mid = CLLocationCoordinate2D(latitude: 37.7745, longitude: -122.4190)
        let seg1ScreenPoint = mapView.convert(seg1Mid, toPointTo: mapView)

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

    // MARK: - Maximum-Fidelity Trajectory Reconstruction & Uncertainty Tests

    func testMixedRouteWalkingStationaryDwellWalking() {
        let baseDate = Date(timeIntervalSince1970: 1772900000)
        var points: [TrajectoryPoint] = []

        // 1. Walk 1: 5 points advancing ~22m every 10s (~88m total)
        for i in 0..<5 {
            points.append(
                TrajectoryPoint(
                    latitude: 37.7741 + Double(i) * 0.0002,
                    longitude: -122.4191,
                    timestamp: baseDate.addingTimeInterval(Double(i * 10)),
                    horizontalAccuracy: 10.0
                )
            )
        }

        // 2. Stationary Dwell at destination: 41 points spanning 1200s (20 minutes, 30s intervals) with jitter within ~3m
        let dwellAnchor = points.last! // 37.7749, -122.4191
        let dwellStartTime = dwellAnchor.timestamp // t = 40s
        for i in 1...40 {
            let jitterLat = dwellAnchor.latitude + Double(i % 3) * 0.00002
            let jitterLon = dwellAnchor.longitude + Double(i % 2) * 0.00002
            points.append(
                TrajectoryPoint(
                    latitude: jitterLat,
                    longitude: jitterLon,
                    timestamp: dwellStartTime.addingTimeInterval(Double(i * 30)),
                    horizontalAccuracy: 15.0
                )
            )
        }
        let dwellEndTime = dwellStartTime.addingTimeInterval(40 * 30) // t = 1240s

        // 3. Walk 2: 5 points advancing ~22m every 10s (~88m total) departing from dwell location
        for i in 1...4 {
            points.append(
                TrajectoryPoint(
                    latitude: dwellAnchor.latitude + Double(i) * 0.0002,
                    longitude: -122.4191,
                    timestamp: dwellEndTime.addingTimeInterval(Double(i * 10)),
                    horizontalAccuracy: 10.0
                )
            )
        }

        XCTAssertEqual(points.count, 49) // 5 walk1 + 40 dwell + 4 walk2

        let analysis = TrajectoryMath.analyzeDay(points: points)
        XCTAssertEqual(analysis.rawCount, 49, "All 49 raw fixes must be preserved in analysis metrics")
        XCTAssertEqual(analysis.segments.count, 2, "Walk -> 20min jitter -> Walk must break rendered motion into 2 clean trajectory segments")
        XCTAssertEqual(analysis.singletons.count, 1, "Stationary jitter must be preserved as 1 dwell observation singleton")
        XCTAssertEqual(analysis.singletons[0].observationDuration, 1200.0, accuracy: 0.1, "Dwell singleton must preserve full 1200s (20 min) continuous observation duration")
        XCTAssertEqual(analysis.segments[0].points.count, 5, "Walk 1 segment must have 5 points ending at destination")
        XCTAssertEqual(analysis.segments[1].points.count, 5, "Walk 2 segment must have 5 points departing from destination")
    }

    func testSameTimestampConflictingDistantCoordinates() {
        let baseDate = Date(timeIntervalSince1970: 1772900000)
        let points = [
            // Segment 1 (SF location)
            TrajectoryPoint(latitude: 37.7741, longitude: -122.4191, timestamp: baseDate, horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7743, longitude: -122.4193, timestamp: baseDate.addingTimeInterval(30), horizontalAccuracy: 10.0),
            // Conflicting distant coordinate (~2.2km away) reported at the exact same timestamp (t=30s)
            TrajectoryPoint(latitude: 37.7940, longitude: -122.4192, timestamp: baseDate.addingTimeInterval(30), horizontalAccuracy: 10.0),
            // Subsequent movement from the second coordinate
            TrajectoryPoint(latitude: 37.7942, longitude: -122.4194, timestamp: baseDate.addingTimeInterval(60), horizontalAccuracy: 10.0)
        ]

        let analysis = TrajectoryMath.analyzeDay(points: points)
        XCTAssertEqual(analysis.rawCount, 4, "Raw count must preserve all 4 fixes including conflicting same-timestamp coords")
        XCTAssertEqual(analysis.segments.count, 2, "Conflicting distant coordinates at same timestamp must not be swallowed as duplicate; must act as barrier/split")
        XCTAssertEqual(analysis.segments[0].points.count, 2)
        XCTAssertEqual(analysis.segments[1].points.count, 2)
    }

    func testStationaryUncertaintyJitterSuppression() {
        let baseDate = Date(timeIntervalSince1970: 1772900000)
        var jitterPoints: [TrajectoryPoint] = []
        for i in 0..<20 {
            // Points jittering within ~4m of anchor (37.7749, -122.4194)
            let lat = 37.7749 + Double(i % 4) * 0.00003
            let lon = -122.4194 + Double(i % 3) * 0.00003
            jitterPoints.append(
                TrajectoryPoint(
                    latitude: lat,
                    longitude: lon,
                    timestamp: baseDate.addingTimeInterval(Double(i * 30)),
                    horizontalAccuracy: 15.0
                )
            )
        }

        let analysis = TrajectoryMath.analyzeDay(points: jitterPoints)
        XCTAssertEqual(analysis.rawCount, 20)
        XCTAssertEqual(analysis.usableCount, 20)
        XCTAssertEqual(analysis.outlierCount, 0)
        XCTAssertTrue(analysis.segments.isEmpty, "Stationary jitter within uncertainty radius must not fabricate movement polylines")
        XCTAssertEqual(analysis.singletons.count, 1, "Stationary jitter must be preserved as 1 dwell observation")
        XCTAssertEqual(analysis.singletons[0].observationDuration, 570.0, accuracy: 0.1, "Dwell observation duration must equal continuous span")
    }

    func testSlowCumulativeWalkingNotSwallowed() {
        let baseDate = Date(timeIntervalSince1970: 1772900000)
        var walkPoints: [TrajectoryPoint] = []
        // 10 points advancing continuously ~5.5m per 10s step -> total ~50m
        for i in 0..<10 {
            let lat = 37.7749 + Double(i) * 0.00005
            let lon = -122.4194
            walkPoints.append(
                TrajectoryPoint(
                    latitude: lat,
                    longitude: lon,
                    timestamp: baseDate.addingTimeInterval(Double(i * 10)),
                    horizontalAccuracy: 10.0
                )
            )
        }

        let analysis = TrajectoryMath.analyzeDay(points: walkPoints)
        XCTAssertEqual(analysis.segments.count, 1, "Slow cumulative walking must be preserved as a continuous trajectory segment")
        XCTAssertEqual(analysis.segments[0].points.count, 10, "All 10 walk points must be retained in the segment")
        XCTAssertTrue(analysis.singletons.isEmpty)
    }

    func testStationaryDwellDoesNotCrossGap() {
        let baseDate = Date(timeIntervalSince1970: 1772900000)
        var points: [TrajectoryPoint] = []
        // Cluster 1: 5 points spanning 120s
        for i in 0..<5 {
            points.append(
                TrajectoryPoint(
                    latitude: 37.7749,
                    longitude: -122.4194,
                    timestamp: baseDate.addingTimeInterval(Double(i * 30)),
                    horizontalAccuracy: 15.0
                )
            )
        }
        // 1000s gap
        let gapStart = baseDate.addingTimeInterval(120 + 1000)
        // Cluster 2: 5 points spanning 120s
        for i in 0..<5 {
            points.append(
                TrajectoryPoint(
                    latitude: 37.7749,
                    longitude: -122.4194,
                    timestamp: gapStart.addingTimeInterval(Double(i * 30)),
                    horizontalAccuracy: 15.0
                )
            )
        }

        let analysis = TrajectoryMath.analyzeDay(points: points)
        XCTAssertEqual(analysis.gapCount, 1)
        XCTAssertEqual(analysis.maxGapSeconds, 1000.0, accuracy: 0.1)
        XCTAssertEqual(analysis.singletons.count, 2, "Stationary dwell must NOT cross gap; produces 2 distinct singletons")
        XCTAssertEqual(analysis.singletons[0].observationDuration, 120.0, accuracy: 0.1)
        XCTAssertEqual(analysis.singletons[1].observationDuration, 120.0, accuracy: 0.1)
    }

    func testDuplicateTimestampDoesNotSplitSegment() {
        let baseDate = Date(timeIntervalSince1970: 1772900000)
        let points = [
            TrajectoryPoint(latitude: 37.7741, longitude: -122.4191, timestamp: baseDate, horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7743, longitude: -122.4193, timestamp: baseDate.addingTimeInterval(30), horizontalAccuracy: 10.0),
            // Duplicate timestamp at t=30s with coarser accuracy
            TrajectoryPoint(latitude: 37.77435, longitude: -122.41935, timestamp: baseDate.addingTimeInterval(30), horizontalAccuracy: 25.0),
            TrajectoryPoint(latitude: 37.7745, longitude: -122.4195, timestamp: baseDate.addingTimeInterval(60), horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7747, longitude: -122.4197, timestamp: baseDate.addingTimeInterval(90), horizontalAccuracy: 10.0)
        ]

        let analysis = TrajectoryMath.analyzeDay(points: points)
        XCTAssertEqual(analysis.rawCount, 5, "Raw count must include all 5 fixes")
        XCTAssertEqual(analysis.segments.count, 1, "Duplicate timestamps (dt=0) must not split continuous trajectory")
        XCTAssertEqual(analysis.segments[0].points.count, 4, "De-duplicated display segment must contain 4 distinct points keeping better accuracy")
    }

    func testNilIsBackgroundCountedAsUnknownNotForeground() {
        let baseDate = Date(timeIntervalSince1970: 1772900000)
        let points = [
            TrajectoryPoint(latitude: 37.7741, longitude: -122.4191, timestamp: baseDate, horizontalAccuracy: 10.0, isBackground: true),
            TrajectoryPoint(latitude: 37.7742, longitude: -122.4192, timestamp: baseDate.addingTimeInterval(30), horizontalAccuracy: 10.0, isBackground: false),
            TrajectoryPoint(latitude: 37.7743, longitude: -122.4193, timestamp: baseDate.addingTimeInterval(60), horizontalAccuracy: 10.0, isBackground: nil)
        ]

        let analysis = TrajectoryMath.analyzeDay(points: points)
        XCTAssertEqual(analysis.backgroundCount, 1)
        XCTAssertEqual(analysis.foregroundCount, 1)
        XCTAssertEqual(analysis.unknownLifecycleCount, 1, "nil isBackground must be counted as unknown, not foreground")
    }

    func testGapsAcrossPoorObservationsAreCounted() {
        let baseDate = Date(timeIntervalSince1970: 1772900000)
        let points = [
            TrajectoryPoint(latitude: 37.7741, longitude: -122.4191, timestamp: baseDate, horizontalAccuracy: 10.0),
            // Outlier at t=100s
            TrajectoryPoint(latitude: 37.7742, longitude: -122.4192, timestamp: baseDate.addingTimeInterval(100), horizontalAccuracy: 350.0),
            // Outlier at t=600s (gap of 500s from previous observation)
            TrajectoryPoint(latitude: 37.7743, longitude: -122.4193, timestamp: baseDate.addingTimeInterval(600), horizontalAccuracy: 400.0),
            // Usable fix at t=1200s (gap of 600s from previous observation)
            TrajectoryPoint(latitude: 37.7744, longitude: -122.4194, timestamp: baseDate.addingTimeInterval(1200), horizontalAccuracy: 10.0)
        ]

        let analysis = TrajectoryMath.analyzeDay(points: points)
        XCTAssertEqual(analysis.rawCount, 4)
        XCTAssertEqual(analysis.usableCount, 2)
        XCTAssertEqual(analysis.outlierCount, 2)
        XCTAssertGreaterThanOrEqual(analysis.gapCount, 2, "Gaps across poor fixes in raw observation timeline must be counted")
        XCTAssertEqual(analysis.maxGapSeconds, 600.0, accuracy: 0.1)
    }

    func testPoorFixBarrierSplitsSegments() {
        let baseDate = Date(timeIntervalSince1970: 1772900000)
        let points = [
            TrajectoryPoint(latitude: 37.7741, longitude: -122.4191, timestamp: baseDate, horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7743, longitude: -122.4193, timestamp: baseDate.addingTimeInterval(30), horizontalAccuracy: 10.0),
            // Poor fix barrier (horizontal accuracy 350m > 200m)
            TrajectoryPoint(latitude: 37.7745, longitude: -122.4195, timestamp: baseDate.addingTimeInterval(60), horizontalAccuracy: 350.0),
            TrajectoryPoint(latitude: 37.7747, longitude: -122.4197, timestamp: baseDate.addingTimeInterval(90), horizontalAccuracy: 10.0),
            TrajectoryPoint(latitude: 37.7749, longitude: -122.4199, timestamp: baseDate.addingTimeInterval(120), horizontalAccuracy: 10.0)
        ]

        let analysis = TrajectoryMath.analyzeDay(points: points)
        XCTAssertEqual(analysis.rawCount, 5)
        XCTAssertEqual(analysis.usableCount, 4)
        XCTAssertEqual(analysis.outlierCount, 1)
        XCTAssertEqual(analysis.segments.count, 2, "Poor fix must act as a barrier and split into 2 distinct segments")
        XCTAssertEqual(analysis.segments[0].points.count, 2)
        XCTAssertEqual(analysis.segments[1].points.count, 2)
        XCTAssertTrue(analysis.singletons.isEmpty)
    }

    func testSingletonPreservation() {
        let baseDate = Date(timeIntervalSince1970: 1772900000)
        let points = [
            // Isolated singleton 1 (gap of 600s follows)
            TrajectoryPoint(latitude: 37.7740, longitude: -122.4190, timestamp: baseDate, horizontalAccuracy: 8.0),
            // Continuous segment (p2 -> p3)
            TrajectoryPoint(latitude: 37.7750, longitude: -122.4195, timestamp: baseDate.addingTimeInterval(600), horizontalAccuracy: 12.0),
            TrajectoryPoint(latitude: 37.7755, longitude: -122.4199, timestamp: baseDate.addingTimeInterval(630), horizontalAccuracy: 12.0),
            // Isolated singleton 2 (gap of 600s after segment)
            TrajectoryPoint(latitude: 37.7760, longitude: -122.4200, timestamp: baseDate.addingTimeInterval(1300), horizontalAccuracy: 15.0)
        ]

        let analysis = TrajectoryMath.analyzeDay(points: points)
        XCTAssertEqual(analysis.rawCount, 4)
        XCTAssertEqual(analysis.usableCount, 4)
        XCTAssertEqual(analysis.segments.count, 1)
        XCTAssertEqual(analysis.singletons.count, 2, "Both isolated points must be preserved as singletons")
        XCTAssertEqual(analysis.singletons[0].point.timestamp, baseDate)
        XCTAssertEqual(analysis.singletons[1].point.timestamp, baseDate.addingTimeInterval(1300))
    }

    func testNonPhysicalSpeedJump() {
        let baseDate = Date(timeIntervalSince1970: 1772900000)
        let points = [
            // p1
            TrajectoryPoint(latitude: 37.7740, longitude: -122.4190, timestamp: baseDate, horizontalAccuracy: 10.0),
            // p2: Jump of ~800m in 10s = 80 m/s > 50 m/s -> splits
            TrajectoryPoint(latitude: 37.7812, longitude: -122.4190, timestamp: baseDate.addingTimeInterval(10), horizontalAccuracy: 10.0),
            // p3: Normal walking from p2 (25m in 10s = 2.5 m/s)
            TrajectoryPoint(latitude: 37.7815, longitude: -122.4190, timestamp: baseDate.addingTimeInterval(20), horizontalAccuracy: 10.0)
        ]

        let analysis = TrajectoryMath.analyzeDay(points: points)
        XCTAssertEqual(analysis.segments.count, 1)
        XCTAssertEqual(analysis.singletons.count, 1)
        XCTAssertEqual(analysis.singletons[0].point.timestamp, baseDate)
        XCTAssertEqual(analysis.segments[0].points.count, 2)
    }

    func testTrajectoryDayAnalysisMetrics() {
        let baseDate = Date(timeIntervalSince1970: 1772900000)
        let points = [
            TrajectoryPoint(latitude: 37.7741, longitude: -122.4191, timestamp: baseDate, horizontalAccuracy: 10.0, isBackground: true),
            TrajectoryPoint(latitude: 37.7742, longitude: -122.4192, timestamp: baseDate.addingTimeInterval(30), horizontalAccuracy: 20.0, isBackground: true),
            // 400s gap
            TrajectoryPoint(latitude: 37.7743, longitude: -122.4193, timestamp: baseDate.addingTimeInterval(430), horizontalAccuracy: 5.0, isBackground: false),
            // Outlier fix > 200m
            TrajectoryPoint(latitude: 37.7744, longitude: -122.4194, timestamp: baseDate.addingTimeInterval(460), horizontalAccuracy: 300.0, isBackground: false)
        ]

        let analysis = TrajectoryMath.analyzeDay(points: points)
        XCTAssertEqual(analysis.rawCount, 4)
        XCTAssertEqual(analysis.usableCount, 3)
        XCTAssertEqual(analysis.outlierCount, 1)
        XCTAssertEqual(analysis.gapCount, 1)
        XCTAssertEqual(analysis.maxGapSeconds, 400.0, accuracy: 0.1)
        XCTAssertEqual(analysis.medianAccuracy, 10.0, accuracy: 0.1)
        XCTAssertEqual(analysis.worstAccuracy, 20.0, accuracy: 0.1)
        XCTAssertEqual(analysis.backgroundCount, 2)
        XCTAssertEqual(analysis.foregroundCount, 2)
        XCTAssertEqual(analysis.unknownLifecycleCount, 0)
    }

    // MARK: - Map Viewport Stability & Controls Tests

    func testOverlayPreservesSingletonsAndSegments() {
        let coordinator = TrajectoryMapView.Coordinator()
        let mapView = MKMapView()

        let baseDate = Date(timeIntervalSince1970: 1772900000)
        let segPoints = [
            TrajectoryPoint(latitude: 37.77, longitude: -122.42, timestamp: baseDate),
            TrajectoryPoint(latitude: 37.78, longitude: -122.41, timestamp: baseDate.addingTimeInterval(60))
        ]
        let singlePt = TrajectoryPoint(latitude: 37.79, longitude: -122.40, timestamp: baseDate.addingTimeInterval(500), horizontalAccuracy: 15.0)

        let segment = TrajectorySegment(id: "seg_1", points: segPoints)
        let singleton = TrajectorySingleton(id: "single_1", point: singlePt)

        let polyline = SegmentPolyline.create(from: segment)
        let circle = SingletonCircleOverlay.create(from: singleton)

        coordinator.selectedSegmentID = nil

        guard let polyRenderer = coordinator.mapView(mapView, rendererFor: polyline) as? MKPolylineRenderer else {
            XCTFail("Polyline renderer must be MKPolylineRenderer")
            return
        }
        XCTAssertEqual(polyRenderer.lineWidth, 3.5)

        guard let circleRenderer = coordinator.mapView(mapView, rendererFor: circle) as? MKCircleRenderer else {
            XCTFail("Circle renderer must be MKCircleRenderer")
            return
        }
        XCTAssertEqual(circleRenderer.lineWidth, 1.5)
    }

    func testDebugOverlayGeneratesAnnotationsForRawPoints() {
        let coordinator = TrajectoryMapView.Coordinator()
        let mapView = MKMapView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))

        let baseDate = Date(timeIntervalSince1970: 1772900000)
        let rawPoints = [
            TrajectoryPoint(latitude: 37.77, longitude: -122.42, timestamp: baseDate, horizontalAccuracy: 15.0),
            TrajectoryPoint(latitude: 37.78, longitude: -122.41, timestamp: baseDate.addingTimeInterval(30), horizontalAccuracy: 150.0), // suspicious
            TrajectoryPoint(latitude: 37.79, longitude: -122.40, timestamp: baseDate.addingTimeInterval(60), horizontalAccuracy: 350.0)  // outlier
        ]

        _ = coordinator.updateMapOverlays(
            mapView: mapView,
            segments: [],
            singletons: [],
            rawPoints: rawPoints,
            showDebugOverlay: true,
            dayKey: "2026-03-08"
        )

        XCTAssertEqual(coordinator.debugOverlays.count, 3, "Debug overlay must generate annotations for all raw points")
        XCTAssertEqual(coordinator.debugOverlays[0].status, .usable)
        XCTAssertEqual(coordinator.debugOverlays[1].status, .suspicious)
        XCTAssertEqual(coordinator.debugOverlays[2].status, .outlier)
    }

    func testViewportFramingOnlyOnDateChange() {
        let coordinator = TrajectoryMapView.Coordinator()
        let mapView = MKMapView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))

        let baseDate = Date(timeIntervalSince1970: 1772900000)
        let dayKey1 = "2026-03-08"
        let dayKey2 = "2026-03-09"

        let seg1 = TrajectorySegment(id: "s1", points: [
            TrajectoryPoint(latitude: 37.77, longitude: -122.42, timestamp: baseDate),
            TrajectoryPoint(latitude: 37.78, longitude: -122.41, timestamp: baseDate.addingTimeInterval(60))
        ])

        // First render on dayKey1 -> should trigger framing
        let didFrameFirst = coordinator.updateMapOverlays(
            mapView: mapView,
            segments: [seg1],
            singletons: [],
            rawPoints: [],
            showDebugOverlay: false,
            dayKey: dayKey1
        )
        XCTAssertTrue(didFrameFirst, "Initial load for dayKey1 must trigger framing")

        // Same dayKey1 with new incremental point -> must NOT reframe
        let seg1Updated = TrajectorySegment(id: "s1", points: [
            TrajectoryPoint(latitude: 37.77, longitude: -122.42, timestamp: baseDate),
            TrajectoryPoint(latitude: 37.78, longitude: -122.41, timestamp: baseDate.addingTimeInterval(60)),
            TrajectoryPoint(latitude: 37.785, longitude: -122.405, timestamp: baseDate.addingTimeInterval(90))
        ])
        let didFrameIncremental = coordinator.updateMapOverlays(
            mapView: mapView,
            segments: [seg1Updated],
            singletons: [],
            rawPoints: [],
            showDebugOverlay: false,
            dayKey: dayKey1
        )
        XCTAssertFalse(didFrameIncremental, "Incremental point update for same dayKey must NOT reframe viewport")

        // Date navigation to dayKey2 -> must trigger framing
        let didFrameNewDay = coordinator.updateMapOverlays(
            mapView: mapView,
            segments: [],
            singletons: [],
            rawPoints: [],
            showDebugOverlay: false,
            dayKey: dayKey2
        )
        XCTAssertTrue(didFrameNewDay, "Date change to dayKey2 must trigger framing")
    }

    func testDefaultContinuityPolicyAndGapRegression() {
        let baseDate = Date(timeIntervalSince1970: 1772900000)
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

        // 1. By DEFAULT (<=30s threshold): 40s, 120s, 299s gaps do NOT connect -> splits into 4 separate segments
        let defaultSegs = TrajectoryMath.segment(points: multiGapPoints)
        XCTAssertEqual(defaultSegs.count, 4, "40s, 120s, 299s gaps must split into 4 segments by default")
        for seg in defaultSegs {
            XCTAssertEqual(seg.points.count, 2)
        }

        let multiGapAnalysis = TrajectoryMath.analyzeDay(points: multiGapPoints)
        XCTAssertEqual(multiGapAnalysis.rawCount, 8, "Raw count must preserve all 8 points")
        XCTAssertEqual(multiGapAnalysis.usableCount, 8)
        XCTAssertEqual(multiGapAnalysis.gapCount, 3, "Timeline must identify 3 gaps (>30s)")
        XCTAssertEqual(multiGapAnalysis.maxGapSeconds, 299.0, accuracy: 0.001)

        // 2. Explicit override (maxTimeGapSeconds: 300s): all gaps connect into 1 continuous segment
        let override300Segs = TrajectoryMath.segment(points: multiGapPoints, maxTimeGapSeconds: 300.0)
        XCTAssertEqual(override300Segs.count, 1, "Explicit 300s gap override should connect all 40s/120s/299s gaps into 1 segment")
        XCTAssertEqual(override300Segs[0].points.count, 8)

        // 3. Dwell must NOT bridge across 40s, 120s, or 299s gaps
        var splitDwellPoints: [TrajectoryPoint] = []
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
        // 40s gap
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
        XCTAssertEqual(splitDwellAnalysis.rawCount, 10)
        XCTAssertTrue(splitDwellAnalysis.segments.isEmpty)
        XCTAssertEqual(splitDwellAnalysis.singletons.count, 2, "Stationary dwell must NOT bridge across 40s gap; produces 2 distinct singletons")
        XCTAssertEqual(splitDwellAnalysis.singletons[0].observationDuration, 20.0, accuracy: 0.1)
        XCTAssertEqual(splitDwellAnalysis.singletons[1].observationDuration, 20.0, accuracy: 0.1)
    }

    func testSmooth1HzWalkingContinuous() {
        let baseDate = Date(timeIntervalSince1970: 1772900000)
        var smoothWalkPoints: [TrajectoryPoint] = []
        for i in 0..<60 {
            smoothWalkPoints.append(
                TrajectoryPoint(
                    latitude: 37.7741 + Double(i) * 0.000015,
                    longitude: -122.4191,
                    timestamp: baseDate.addingTimeInterval(Double(i)),
                    horizontalAccuracy: 5.0
                )
            )
        }
        let analysis = TrajectoryMath.analyzeDay(points: smoothWalkPoints)
        XCTAssertEqual(analysis.rawCount, 60)
        XCTAssertEqual(analysis.segments.count, 1, "Continuous 1Hz smooth walking must produce exactly 1 continuous segment")
        XCTAssertEqual(analysis.segments[0].points.count, 60)
        XCTAssertTrue(analysis.singletons.isEmpty)
        XCTAssertEqual(analysis.gapCount, 0)
    }

    // MARK: - HealthKit StepCountReader & Details Sheet Tests

    func testStepCountFormatting() {
        XCTAssertEqual(StepCountReader.formatStepCount(nil), "Steps unavailable")
        XCTAssertEqual(StepCountReader.formatStepCount(0), "0 steps")
        XCTAssertEqual(StepCountReader.formatStepCount(1), "1 step")
        XCTAssertEqual(StepCountReader.formatStepCount(42), "42 steps")

        let thousandFormatted = StepCountReader.formatStepCount(1000)
        XCTAssertTrue(thousandFormatted.contains("1,000") || thousandFormatted.contains("1000"), "Must contain formatted 1000 steps")
        XCTAssertTrue(thousandFormatted.hasSuffix("steps"))
    }

    func testDurationMinutesFormatting() {
        XCTAssertEqual(StepCountReader.formatDurationMinutes(0.0), "1 min")
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

    func testSamplePredicateConstruction() {
        let start = Date(timeIntervalSince1970: 1772900000)
        let end = Date(timeIntervalSince1970: 1772901800)
        let predicate = StepCountReader.makeSamplePredicate(startDate: start, endDate: end)
        XCTAssertNotNil(predicate)
        let predicateFormat = predicate.predicateFormat
        XCTAssertFalse(predicateFormat.isEmpty, "Sample predicate format must be valid")
    }

    func testInvalidQueryIntervalGuard() async {
        let reader = StepCountReader.shared
        let now = Date()
        let past = now.addingTimeInterval(-60)

        let resultReversed = await reader.fetchStepCount(startDate: now, endDate: past)
        XCTAssertNil(resultReversed, "Reversed date interval must safely return nil")

        let resultEqual = await reader.fetchStepCount(startDate: now, endDate: now)
        XCTAssertNil(resultEqual, "Zero-duration date interval must safely return nil")
    }

    // MARK: - Native MapKit Display Mode & Time Heatmap Tests

    func testMapDisplayModePathVsTimeOverlays() {
        let coordinator = TrajectoryMapView.Coordinator()
        let mapView = MKMapView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))

        let t0 = Date(timeIntervalSince1970: 1772900000)
        let p1 = TrajectoryPoint(latitude: 37.7749, longitude: -122.4194, timestamp: t0)
        let p2 = TrajectoryPoint(latitude: 37.7759, longitude: -122.4194, timestamp: t0.addingTimeInterval(10))
        let segment = TrajectorySegment(points: [p1, p2])

        let stay = DayStay(
            id: "stay_1",
            latitude: 37.7770,
            longitude: -122.4194,
            arrivalDate: t0.addingTimeInterval(100),
            departureDate: t0.addingTimeInterval(1900),
            duration: 1800.0,
            horizontalAccuracy: 8.0,
            assignedPlaceLabel: "Place 1"
        )

        // 1. In Path mode: overlay count must include polylines and stay circles
        _ = coordinator.updateMapOverlays(
            mapView: mapView,
            segments: [segment],
            stays: [stay],
            singleObservations: [],
            displayMode: .path,
            dayKey: "day_1"
        )

        let polylineOverlays = mapView.overlays.compactMap { $0 as? SegmentPolyline }
        let stayOverlays = mapView.overlays.compactMap { $0 as? StayCircleOverlay }
        let heatOverlays = mapView.overlays.compactMap { $0 as? DwellHeatOverlay }

        XCTAssertEqual(polylineOverlays.count, 1, "Path mode must render segment polylines")
        XCTAssertEqual(stayOverlays.count, 1, "Path mode must render stay circles")
        XCTAssertEqual(heatOverlays.count, 0, "Path mode must not render heat overlays")

        // 2. In Time mode: overlay count must include heat overlays only (no trajectory polylines)
        _ = coordinator.updateMapOverlays(
            mapView: mapView,
            segments: [segment],
            stays: [stay],
            singleObservations: [],
            displayMode: .time,
            dayKey: "day_1_time"
        )

        let polylineOverlaysTime = mapView.overlays.compactMap { $0 as? SegmentPolyline }
        let stayOverlaysTime = mapView.overlays.compactMap { $0 as? StayCircleOverlay }
        let heatOverlaysTime = mapView.overlays.compactMap { $0 as? DwellHeatOverlay }

        XCTAssertEqual(polylineOverlaysTime.count, 0, "Time mode must hide polylines")
        XCTAssertEqual(stayOverlaysTime.count, 0, "Time mode replaces standard stay circles with heat overlays")
        XCTAssertEqual(heatOverlaysTime.count, 1, "Time mode must render dwell heat overlays")
    }

    func testDwellHeatOverlayRadiusScalingWithDuration() {
        let t0 = Date(timeIntervalSince1970: 1772900000)
        let shortStay = DayStay(
            id: "short",
            latitude: 37.77,
            longitude: -122.41,
            arrivalDate: t0,
            departureDate: t0.addingTimeInterval(300), // 5 min
            duration: 300.0,
            horizontalAccuracy: 5.0
        )
        let longStay = DayStay(
            id: "long",
            latitude: 37.78,
            longitude: -122.42,
            arrivalDate: t0,
            departureDate: t0.addingTimeInterval(14400), // 4 hours
            duration: 14400.0,
            horizontalAccuracy: 5.0
        )

        let shortHeat = DwellHeatOverlay.create(from: shortStay)
        let longHeat = DwellHeatOverlay.create(from: longStay)

        XCTAssertGreaterThan(longHeat.radius, shortHeat.radius, "Longer dwell must produce a larger heat overlay radius")
        XCTAssertGreaterThan(shortHeat.radius, 15.0)
    }

    // MARK: - DayDetailView Model & Structure Tests

    func testDayDetailTopFivePlacesTruncation() {
        var places: [DayPlace] = []
        let now = Date()
        for i in 1...8 {
            places.append(
                DayPlace(
                    id: "place_\(i)",
                    label: "Place \(i)",
                    latitude: 37.77 + Double(i) * 0.01,
                    longitude: -122.41,
                    totalDuration: Double(i * 600), // 10m, 20m, ..., 80m
                    visitCount: 1,
                    firstArrival: now,
                    lastDeparture: now.addingTimeInterval(Double(i * 600))
                )
            )
        }

        let top5 = DayDetailView.topPlaces(from: places, limit: 5)
        XCTAssertEqual(top5.count, 5, "Must truncate to exactly top 5 places")
        XCTAssertEqual(top5.first?.label, "Place 8", "Highest duration place must be first")
        XCTAssertEqual(top5.last?.label, "Place 4", "Fifth highest duration place must be last in top 5")
    }

    func testDayDetailDonutBreakdownSlices() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let day = cal.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let now = day.addingTimeInterval(86400 * 2)

        let history = DayHistory.build(points: [], selectedDate: day, now: now, calendar: cal)
        let slices = DayDetailView.breakdownSlices(for: history)

        XCTAssertEqual(slices.count, 3)
        let total = slices.reduce(0.0) { $0 + $1.duration }
        XCTAssertEqual(total, history.totalElapsedDuration, accuracy: 0.001)

        let unknownSlice = slices.first(where: { $0.category == .unknown })
        XCTAssertEqual(unknownSlice?.duration, 86400.0)
    }

    func testDistanceExcludesDwellJitterAndGaps() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let day = cal.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let now = day.addingTimeInterval(86400 * 2)

        // 100 jitter points at (37.7749, -122.4194) within 5m
        var points: [TrajectoryPoint] = []
        let dwellStart = day.addingTimeInterval(3600)
        for i in 0...100 {
            let jitterLat = 37.7749 + Double(i % 3 - 1) * 0.00002
            let jitterLon = -122.4194 + Double(i % 3 - 1) * 0.00002
            points.append(TrajectoryPoint(
                latitude: jitterLat,
                longitude: jitterLon,
                timestamp: dwellStart.addingTimeInterval(Double(i * 10)),
                horizontalAccuracy: 5.0
            ))
        }

        let history = DayHistory.build(points: points, selectedDate: day, now: now, calendar: cal)
        XCTAssertEqual(history.observedDistanceMeters, 0.0, "Stationary dwell jitter must not contribute to moving distance")
        XCTAssertEqual(history.stays.count, 1)
    }

    func testFormatObservedBoundsAndDurations() {
        let t1 = Date(timeIntervalSince1970: 1772900000)
        let t2 = t1.addingTimeInterval(3600 + 1800) // 1h 30m

        let boundsStr = DayHistory.formatObservedBounds(start: t1, end: t2)
        XCTAssertTrue(boundsStr.hasPrefix("Observed"))
        XCTAssertTrue(boundsStr.contains("–"))

        let singleBounds = DayHistory.formatObservedBounds(start: t1, end: t1)
        XCTAssertTrue(singleBounds.hasPrefix("Observed at"))

        XCTAssertEqual(DayHistory.formatDistance(500.0), "500 m")
        XCTAssertEqual(DayHistory.formatDistance(3850.0), "3.9 km")

        XCTAssertEqual(DayHistory.formatDuration(0.0), "0m")
        XCTAssertEqual(DayHistory.formatDuration(30.0), "< 1m")
        XCTAssertEqual(DayHistory.formatDuration(300.0), "5m")
        XCTAssertEqual(DayHistory.formatDuration(3600.0), "1h")
        XCTAssertEqual(DayHistory.formatDuration(5400.0), "1h 30m")
    }

    func testCumulativeDistanceDisjointSeriesSegmentation() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let day = cal.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let now = day.addingTimeInterval(86400 * 2)

        // Two walking bouts separated by a 10-minute gap
        var points: [TrajectoryPoint] = []
        let walk1_start = day.addingTimeInterval(3600)
        for i in 0...3 {
            points.append(TrajectoryPoint(
                latitude: 37.770 + Double(i) * 0.001,
                longitude: -122.410,
                timestamp: walk1_start.addingTimeInterval(Double(i * 5)),
                horizontalAccuracy: 5.0
            ))
        }

        let walk2_start = walk1_start.addingTimeInterval(600) // 10 min gap
        for i in 0...3 {
            points.append(TrajectoryPoint(
                latitude: 37.780 + Double(i) * 0.001,
                longitude: -122.410,
                timestamp: walk2_start.addingTimeInterval(Double(i * 5)),
                horizontalAccuracy: 5.0
            ))
        }

        let history = DayHistory.build(points: points, selectedDate: day, now: now, calendar: cal)
        XCTAssertEqual(history.cumulativeDistanceSeries.count, 2, "Disjoint walking bouts separated by gaps must yield separate series arrays")
        XCTAssertEqual(history.cumulativeDistanceSeries[0].count, 4)
        XCTAssertEqual(history.cumulativeDistanceSeries[1].count, 4)
        XCTAssertGreaterThan(history.cumulativeDistanceSeries[1][0].distanceMeters, 0.0, "Second series must start at cumulative distance of first series")
    }

    func testEmptyDayRecenterCoordinatorHandling() {
        let coordinator = TrajectoryMapView.Coordinator()
        let mapView = MKMapView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))

        let didFrame = coordinator.updateMapOverlays(
            mapView: mapView,
            segments: [],
            stays: [],
            singleObservations: [],
            rawPoints: [],
            displayMode: .path,
            dayKey: "empty_day",
            forceRecenter: true
        )

        XCTAssertTrue(didFrame, "Framing on an empty day should complete without error")
        XCTAssertEqual(mapView.overlays.count, 0)
    }
}
