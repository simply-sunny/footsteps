import Foundation

/// Value snapshot representing a single recorded geographical location point.
public struct TrajectoryPoint: Equatable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let timestamp: Date
    public let horizontalAccuracy: Double

    public let altitude: Double?
    public let verticalAccuracy: Double?
    public let speed: Double?
    public let speedAccuracy: Double?
    public let course: Double?
    public let courseAccuracy: Double?
    public let floor: Int?
    public let sourceProvider: String?
    public let isSimulatedBySoftware: Bool?
    public let isProducedByAccessory: Bool?
    public let receivedTimestamp: Date?
    public let sessionID: String?
    public let isBackground: Bool?

    public init(
        latitude: Double,
        longitude: Double,
        timestamp: Date,
        horizontalAccuracy: Double = 0.0,
        altitude: Double? = nil,
        verticalAccuracy: Double? = nil,
        speed: Double? = nil,
        speedAccuracy: Double? = nil,
        course: Double? = nil,
        courseAccuracy: Double? = nil,
        floor: Int? = nil,
        sourceProvider: String? = nil,
        isSimulatedBySoftware: Bool? = nil,
        isProducedByAccessory: Bool? = nil,
        receivedTimestamp: Date? = nil,
        sessionID: String? = nil,
        isBackground: Bool? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.horizontalAccuracy = horizontalAccuracy
        self.altitude = altitude
        self.verticalAccuracy = verticalAccuracy
        self.speed = speed
        self.speedAccuracy = speedAccuracy
        self.course = course
        self.courseAccuracy = courseAccuracy
        self.floor = floor
        self.sourceProvider = sourceProvider
        self.isSimulatedBySoftware = isSimulatedBySoftware
        self.isProducedByAccessory = isProducedByAccessory
        self.receivedTimestamp = receivedTimestamp
        self.sessionID = sessionID
        self.isBackground = isBackground
    }
}

/// An isolated or stationary geographical location observation preserved as historical evidence.
public struct TrajectorySingleton: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let point: TrajectoryPoint
    public let observationDuration: TimeInterval

    public init(
        id: String? = nil,
        point: TrajectoryPoint,
        observationDuration: TimeInterval = 0.0
    ) {
        self.point = point
        self.observationDuration = observationDuration
        if let id = id {
            self.id = id
        } else {
            let tsMs = Int64(point.timestamp.timeIntervalSince1970 * 1000)
            let lat = String(format: "%.5f", point.latitude)
            let lon = String(format: "%.5f", point.longitude)
            self.id = "single_\(tsMs)_\(lat)_\(lon)"
        }
    }
}

/// A contiguous trajectory segment composed of at least 2 chronological points with verified movement.
public struct TrajectorySegment: Identifiable, Equatable, Sendable {
    public let id: String
    public let points: [TrajectoryPoint]

    public var startDate: Date {
        points.first?.timestamp ?? Date.distantPast
    }

    public var endDate: Date {
        points.last?.timestamp ?? Date.distantPast
    }

    public var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }

    public var distanceMeters: Double {
        guard points.count >= 2 else { return 0.0 }
        var total: Double = 0.0
        for i in 0..<(points.count - 1) {
            total += TrajectoryMath.haversineDistance(from: points[i], to: points[i + 1])
        }
        return total
    }

    public init(id: String? = nil, points: [TrajectoryPoint]) {
        self.points = points
        if let id = id {
            self.id = id
        } else if let first = points.first, let last = points.last {
            // Deterministic stable ID derived from point timestamps, count, and endpoint coordinates
            let startMs = Int64(first.timestamp.timeIntervalSince1970 * 1000)
            let endMs = Int64(last.timestamp.timeIntervalSince1970 * 1000)
            let startLat = String(format: "%.5f", first.latitude)
            let startLon = String(format: "%.5f", first.longitude)
            let endLat = String(format: "%.5f", last.latitude)
            let endLon = String(format: "%.5f", last.longitude)
            self.id = "seg_\(startMs)_\(endMs)_\(points.count)_\(startLat)_\(startLon)_\(endLat)_\(endLon)"
        } else {
            self.id = "seg_empty"
        }
    }
}

/// Comprehensive daily trajectory reconstruction and evidence analysis.
public struct TrajectoryDayAnalysis: Equatable, Sendable {
    public let segments: [TrajectorySegment]
    public let singletons: [TrajectorySingleton]
    public let rawCount: Int
    public let usableCount: Int
    public let suspiciousCount: Int
    public let outlierCount: Int
    public let gapCount: Int
    public let maxGapSeconds: Double
    public let medianAccuracy: Double
    public let worstAccuracy: Double
    public let backgroundCount: Int
    public let foregroundCount: Int
    public let unknownLifecycleCount: Int

    public init(
        segments: [TrajectorySegment],
        singletons: [TrajectorySingleton],
        rawCount: Int,
        usableCount: Int,
        suspiciousCount: Int = 0,
        outlierCount: Int = 0,
        gapCount: Int = 0,
        maxGapSeconds: Double = 0.0,
        medianAccuracy: Double = 0.0,
        worstAccuracy: Double = 0.0,
        backgroundCount: Int = 0,
        foregroundCount: Int = 0,
        unknownLifecycleCount: Int = 0
    ) {
        self.segments = segments
        self.singletons = singletons
        self.rawCount = rawCount
        self.usableCount = usableCount
        self.suspiciousCount = suspiciousCount
        self.outlierCount = outlierCount
        self.gapCount = gapCount
        self.maxGapSeconds = maxGapSeconds
        self.medianAccuracy = medianAccuracy
        self.worstAccuracy = worstAccuracy
        self.backgroundCount = backgroundCount
        self.foregroundCount = foregroundCount
        self.unknownLifecycleCount = unknownLifecycleCount
    }
}

public enum TrajectoryMath {
    /// Max acceptable horizontal accuracy in meters for display segments (200m).
    public static let defaultMaxHorizontalAccuracy: Double = 200.0

    /// Suspicious horizontal accuracy boundary in meters (100m).
    public static let defaultSuspiciousAccuracyThreshold: Double = 100.0

    /// Conservative provisional continuity ceiling in seconds (30.0 seconds).
    ///
    /// This threshold defines the default display continuity policy for trajectory reconstruction:
    /// - Under continuous high-rate BestForNavigation recording (with ~1Hz pedestrian fixes during active walking),
    ///   consecutive fixes separated by <= 30.0s are treated as continuous movement.
    /// - Gaps exceeding 30.0s (such as unobserved 40s, 120s, or 299s intervals) are treated as discontinuities;
    ///   the reconstruction engine deliberately splits segments and preserves observations as separate
    ///   uncertain observations (singletons, stationary dwell circles, or separate segments) rather than
    ///   inventing speculative straight-line chords across unobserved space.
    /// - Grounded in the legacy dataset median (~33.4s) and burst cadence, while prioritizing spatial uncertainty
    ///   over invented lines per user preference.
    /// - Policy notice: This threshold is a conservative display continuity policy, NOT a location guarantee or
    ///   scientifically calibrated physical boundary, and unavoidable interpolation remains between adjacent
    ///   fixes within the <=30s sampling window (unvalidated outdoor baseline).
    public static let defaultMaxTimeGapSeconds: Double = 30.0

    /// Max speed between consecutive points before splitting (50 m/s = 180 km/h).
    public static let defaultMaxSpeedMetersPerSecond: Double = 50.0

    /// Max distance jump between consecutive points before splitting (10,000 meters = 10 km).
    public static let defaultMaxDistanceMeters: Double = 10_000.0

    // MARK: - Validation

    public static func isValid(
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: Double,
        maxHorizontalAccuracy: Double = defaultMaxHorizontalAccuracy
    ) -> Bool {
        guard latitude.isFinite, longitude.isFinite, horizontalAccuracy.isFinite else { return false }
        guard latitude >= -90.0 && latitude <= 90.0 else { return false }
        guard longitude >= -180.0 && longitude <= 180.0 else { return false }
        guard horizontalAccuracy >= 0.0 && horizontalAccuracy <= maxHorizontalAccuracy else { return false }
        return true
    }

    public static func isValid(
        point: TrajectoryPoint,
        maxHorizontalAccuracy: Double = defaultMaxHorizontalAccuracy
    ) -> Bool {
        isValid(
            latitude: point.latitude,
            longitude: point.longitude,
            horizontalAccuracy: point.horizontalAccuracy,
            maxHorizontalAccuracy: maxHorizontalAccuracy
        )
    }

    // MARK: - Distance Calculations

    /// Earth radius in meters (WGS 84 mean radius).
    private static let earthRadiusMeters: Double = 6_371_000.0

    /// Great-circle distance between two coordinates using the Haversine formula.
    public static func haversineDistance(
        lat1: Double,
        lon1: Double,
        lat2: Double,
        lon2: Double
    ) -> Double {
        let dLat = (lat2 - lat1) * .pi / 180.0
        let dLon = (lon2 - lon1) * .pi / 180.0
        let lat1Rad = lat1 * .pi / 180.0
        let lat2Rad = lat2 * .pi / 180.0

        let sinDLat2 = sin(dLat / 2.0)
        let sinDLon2 = sin(dLon / 2.0)

        let a = sinDLat2 * sinDLat2 + cos(lat1Rad) * cos(lat2Rad) * sinDLon2 * sinDLon2
        let clampedA = max(0.0, min(1.0, a))
        let c = 2.0 * atan2(sqrt(clampedA), sqrt(max(0.0, 1.0 - clampedA)))
        return earthRadiusMeters * c
    }

    public static func haversineDistance(from p1: TrajectoryPoint, to p2: TrajectoryPoint) -> Double {
        haversineDistance(lat1: p1.latitude, lon1: p1.longitude, lat2: p2.latitude, lon2: p2.longitude)
    }

    // MARK: - Segmentation & Analysis

    /// Analyzes and segments a sequence of raw location points into continuous trajectories,
    /// uncertainty-aware stationary dwell clusters, and preserved singletons.
    public static func analyzeDay(
        points: [TrajectoryPoint],
        maxHorizontalAccuracy: Double = defaultMaxHorizontalAccuracy,
        suspiciousAccuracyThreshold: Double = defaultSuspiciousAccuracyThreshold,
        maxTimeGapSeconds: Double = defaultMaxTimeGapSeconds,
        maxSpeedMetersPerSecond: Double = defaultMaxSpeedMetersPerSecond,
        maxDistanceMeters: Double = defaultMaxDistanceMeters
    ) -> TrajectoryDayAnalysis {
        let sortedPoints = points.sorted {
            if $0.timestamp != $1.timestamp {
                return $0.timestamp < $1.timestamp
            }
            if let r0 = $0.receivedTimestamp, let r1 = $1.receivedTimestamp, r0 != r1 {
                return r0 < r1
            }
            return $0.horizontalAccuracy < $1.horizontalAccuracy
        }
        let rawCount = sortedPoints.count

        var segments: [TrajectorySegment] = []
        var singletons: [TrajectorySingleton] = []

        var usableCount = 0
        var suspiciousCount = 0
        var outlierCount = 0
        var gapCount = 0
        var maxGapSeconds: Double = 0.0
        var backgroundCount = 0
        var foregroundCount = 0
        var unknownLifecycleCount = 0
        var validAccuracies: [Double] = []

        // 1. Audit raw observation stream for gaps and lifecycle state
        for i in 0..<sortedPoints.count {
            let pt = sortedPoints[i]

            if pt.isBackground == true {
                backgroundCount += 1
            } else if pt.isBackground == false {
                foregroundCount += 1
            } else {
                unknownLifecycleCount += 1
            }

            if i > 0 {
                let dt = pt.timestamp.timeIntervalSince(sortedPoints[i - 1].timestamp)
                if dt > maxTimeGapSeconds {
                    gapCount += 1
                    maxGapSeconds = max(maxGapSeconds, dt)
                }
            }
        }

        // 2. Trajectory reconstruction with anchored stationary grouping and barrier enforcement
        var currentRun: [TrajectoryPoint] = []

        func flushCurrentRun() {
            guard !currentRun.isEmpty else { return }

            if currentRun.count == 1 {
                singletons.append(TrajectorySingleton(point: currentRun[0], observationDuration: 0.0))
                currentRun = []
                return
            }

            // Anchored uncertainty-aware stationary evaluation
            let firstPt = currentRun[0]
            let firstRadius = max(firstPt.horizontalAccuracy, 10.0)
            let maxDisplacement = currentRun.map { haversineDistance(from: firstPt, to: $0) }.max() ?? 0.0

            if maxDisplacement <= firstRadius {
                // Entire run stayed within anchor uncertainty circle: group as stationary dwell observation
                let dwellDuration = currentRun.last!.timestamp.timeIntervalSince(currentRun.first!.timestamp)
                singletons.append(TrajectorySingleton(point: firstPt, observationDuration: dwellDuration))
                currentRun = []
                return
            }

            // Run contains movement; extract local anchored stationary dwell episodes (duration >= 60s)
            // while preserving continuous moving trajectory segments and not swallowing slow cumulative walking.
            let stationaryDurationThreshold: TimeInterval = 60.0
            var movingPoints: [TrajectoryPoint] = []
            var startsFromDwell = false
            var i = 0

            while i < currentRun.count {
                let anchor = currentRun[i]
                let anchorRadius = max(anchor.horizontalAccuracy, 10.0)

                var j = i
                while (j + 1) < currentRun.count && haversineDistance(from: anchor, to: currentRun[j + 1]) <= anchorRadius {
                    j += 1
                }

                let dwellDuration = currentRun[j].timestamp.timeIntervalSince(anchor.timestamp)

                if dwellDuration >= stationaryDurationThreshold && j > i {
                    // Local stationary dwell episode found from index i to j
                    if !movingPoints.isEmpty {
                        movingPoints.append(anchor)
                        if movingPoints.count >= 2 {
                            segments.append(TrajectorySegment(points: movingPoints))
                        } else {
                            singletons.append(TrajectorySingleton(point: movingPoints[0], observationDuration: 0.0))
                        }
                        movingPoints = []
                    }

                    singletons.append(TrajectorySingleton(point: anchor, observationDuration: dwellDuration))
                    movingPoints = [currentRun[j]]
                    startsFromDwell = true
                    i = j + 1
                } else {
                    movingPoints.append(anchor)
                    startsFromDwell = false
                    i += 1
                }
            }

            if !movingPoints.isEmpty {
                if movingPoints.count >= 2 {
                    let anchor = movingPoints[0]
                    let anchorRadius = max(anchor.horizontalAccuracy, 10.0)
                    let maxDisp = movingPoints.map { haversineDistance(from: anchor, to: $0) }.max() ?? 0.0
                    if maxDisp <= anchorRadius {
                        let dwellDuration = movingPoints.last!.timestamp.timeIntervalSince(anchor.timestamp)
                        singletons.append(TrajectorySingleton(point: anchor, observationDuration: dwellDuration))
                    } else {
                        segments.append(TrajectorySegment(points: movingPoints))
                    }
                } else if movingPoints.count == 1 && !startsFromDwell {
                    singletons.append(TrajectorySingleton(point: movingPoints[0], observationDuration: 0.0))
                }
            }

            currentRun = []
        }

        for pt in sortedPoints {
            if !isValid(point: pt, maxHorizontalAccuracy: maxHorizontalAccuracy) {
                outlierCount += 1
                // Poor fix acts as a hard barrier: flushes active run without bridging
                flushCurrentRun()
                continue
            }

            usableCount += 1
            if pt.horizontalAccuracy > suspiciousAccuracyThreshold {
                suspiciousCount += 1
            }
            validAccuracies.append(pt.horizontalAccuracy)

            if let prev = currentRun.last {
                let dt = pt.timestamp.timeIntervalSince(prev.timestamp)
                let dist = haversineDistance(from: prev, to: pt)

                let isNegativeDelta = dt < 0.0
                let isTimeGap = dt > maxTimeGapSeconds
                let isDistanceJump = dist > maxDistanceMeters
                let isSpeedExceeded = dt > 0.0 && (dist / dt) > maxSpeedMetersPerSecond

                if isNegativeDelta || isTimeGap || isDistanceJump || isSpeedExceeded {
                    flushCurrentRun()
                    currentRun = [pt]
                } else if dt == 0.0 {
                    let duplicateThreshold = max(prev.horizontalAccuracy, pt.horizontalAccuracy, 10.0)
                    if dist <= duplicateThreshold {
                        // Harmless duplicate fix at same timestamp: display-only de-duplication retaining better accuracy fix
                        if pt.horizontalAccuracy < prev.horizontalAccuracy {
                            currentRun[currentRun.count - 1] = pt
                        }
                    } else {
                        // Conflicting distant coordinates at same timestamp: treat as barrier/split to preserve uncertainty
                        flushCurrentRun()
                        currentRun = [pt]
                    }
                } else {
                    currentRun.append(pt)
                }
            } else {
                currentRun = [pt]
            }
        }

        flushCurrentRun()

        let sortedAcc = validAccuracies.sorted()
        let medianAccuracy: Double
        if sortedAcc.isEmpty {
            medianAccuracy = 0.0
        } else if sortedAcc.count % 2 == 1 {
            medianAccuracy = sortedAcc[sortedAcc.count / 2]
        } else {
            let mid = sortedAcc.count / 2
            medianAccuracy = (sortedAcc[mid - 1] + sortedAcc[mid]) / 2.0
        }
        let worstAccuracy = sortedAcc.last ?? 0.0

        return TrajectoryDayAnalysis(
            segments: segments,
            singletons: singletons,
            rawCount: rawCount,
            usableCount: usableCount,
            suspiciousCount: suspiciousCount,
            outlierCount: outlierCount,
            gapCount: gapCount,
            maxGapSeconds: maxGapSeconds,
            medianAccuracy: medianAccuracy,
            worstAccuracy: worstAccuracy,
            backgroundCount: backgroundCount,
            foregroundCount: foregroundCount,
            unknownLifecycleCount: unknownLifecycleCount
        )
    }

    /// Splits a sequence of raw location points into contiguous segments based on approved thresholds.
    public static func segment(
        points: [TrajectoryPoint],
        maxHorizontalAccuracy: Double = defaultMaxHorizontalAccuracy,
        suspiciousAccuracyThreshold: Double = defaultSuspiciousAccuracyThreshold,
        maxTimeGapSeconds: Double = defaultMaxTimeGapSeconds,
        maxSpeedMetersPerSecond: Double = defaultMaxSpeedMetersPerSecond,
        maxDistanceMeters: Double = defaultMaxDistanceMeters
    ) -> [TrajectorySegment] {
        analyzeDay(
            points: points,
            maxHorizontalAccuracy: maxHorizontalAccuracy,
            suspiciousAccuracyThreshold: suspiciousAccuracyThreshold,
            maxTimeGapSeconds: maxTimeGapSeconds,
            maxSpeedMetersPerSecond: maxSpeedMetersPerSecond,
            maxDistanceMeters: maxDistanceMeters
        ).segments
    }

    // MARK: - 2D Screen Hit Testing Math

    /// Computes the shortest distance from a 2D point (e.g. tap location) to a 2D line segment.
    public static func distanceFromPointToLineSegment(
        point: (x: Double, y: Double),
        lineStart: (x: Double, y: Double),
        lineEnd: (x: Double, y: Double)
    ) -> Double {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let lengthSquared = dx * dx + dy * dy
        if lengthSquared == 0.0 {
            let px = point.x - lineStart.x
            let py = point.y - lineStart.y
            return (px * px + py * py).squareRoot()
        }
        let t = ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / lengthSquared
        let clampedT = max(0.0, min(1.0, t))
        let projX = lineStart.x + clampedT * dx
        let projY = lineStart.y + clampedT * dy
        let distX = point.x - projX
        let distY = point.y - projY
        return (distX * distX + distY * distY).squareRoot()
    }

    /// Computes the shortest distance from a 2D point to a multi-point polyline.
    public static func distanceFromPointToPolyline(
        point: (x: Double, y: Double),
        polyline: [(x: Double, y: Double)]
    ) -> Double {
        guard polyline.count >= 2 else {
            if let single = polyline.first {
                let dx = point.x - single.x
                let dy = point.y - single.y
                return (dx * dx + dy * dy).squareRoot()
            }
            return .infinity
        }
        var minDistance: Double = .infinity
        for i in 0..<(polyline.count - 1) {
            let d = distanceFromPointToLineSegment(
                point: point,
                lineStart: polyline[i],
                lineEnd: polyline[i + 1]
            )
            if d < minDistance {
                minDistance = d
            }
        }
        return minDistance
    }

    // MARK: - Calendar & Day Interval Helpers

    public static func dayInterval(for date: Date, calendar: Calendar = .current) -> DateInterval {
        let startOfDay = calendar.startOfDay(for: date)
        let nextStartOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(86400)
        return DateInterval(start: startOfDay, end: nextStartOfDay)
    }

    public static func isToday(_ date: Date, calendar: Calendar = .current, now: Date = Date()) -> Bool {
        calendar.isDate(date, inSameDayAs: now)
    }

    public static func canNavigateNext(from date: Date, calendar: Calendar = .current, now: Date = Date()) -> Bool {
        let startOfDate = calendar.startOfDay(for: date)
        let startOfToday = calendar.startOfDay(for: now)
        return startOfDate < startOfToday
    }

    public static func previousDay(from date: Date, calendar: Calendar = .current) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: -1, to: startOfDay) ?? startOfDay.addingTimeInterval(-86400)
    }

    public static func nextDay(from date: Date, calendar: Calendar = .current) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(86400)
    }
}
