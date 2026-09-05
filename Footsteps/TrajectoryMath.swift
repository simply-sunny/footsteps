import Foundation

/// Value snapshot representing a single recorded geographical location point.
public struct TrajectoryPoint: Equatable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let timestamp: Date
    public let horizontalAccuracy: Double

    public init(
        latitude: Double,
        longitude: Double,
        timestamp: Date,
        horizontalAccuracy: Double = 0.0
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.horizontalAccuracy = horizontalAccuracy
    }
}

/// A contiguous trajectory segment composed of at least 2 chronological points.
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

public enum TrajectoryMath {
    /// Max acceptable horizontal accuracy in meters.
    /// LocationManager uses desiredAccuracy = kCLLocationAccuracyHundredMeters (~100m).
    /// Legitimate fixes typically report 5m to 150m accuracy. We filter out fixes >200m
    /// to eliminate coarse cell-tower jumps without dropping normal 100m fixes.
    public static let defaultMaxHorizontalAccuracy: Double = 200.0

    /// Max time gap between consecutive points before splitting into a new segment (5 minutes).
    public static let defaultMaxTimeGapSeconds: Double = 300.0

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

    // MARK: - Segmentation

    /// Splits a sequence of raw location points into contiguous segments based on approved thresholds.
    ///
    /// Segmentation criteria:
    /// - Points are filtered for valid bounds and accuracy (<= maxHorizontalAccuracy)
    /// - Points are sorted chronologically by timestamp
    /// - A new segment begins when:
    ///   1. Nonpositive time delta (dt <= 0)
    ///   2. Time gap > maxTimeGapSeconds (default 300s / 5 min)
    ///   3. Distance jump > maxDistanceMeters (default 10km)
    ///   4. Speed > maxSpeedMetersPerSecond (default 50m/s = 180km/h)
    /// - Segments require at least 2 points; isolated singletons are dropped.
    public static func segment(
        points: [TrajectoryPoint],
        maxHorizontalAccuracy: Double = defaultMaxHorizontalAccuracy,
        maxTimeGapSeconds: Double = defaultMaxTimeGapSeconds,
        maxSpeedMetersPerSecond: Double = defaultMaxSpeedMetersPerSecond,
        maxDistanceMeters: Double = defaultMaxDistanceMeters
    ) -> [TrajectorySegment] {
        let validPoints = points
            .filter { isValid(point: $0, maxHorizontalAccuracy: maxHorizontalAccuracy) }
            .sorted { $0.timestamp < $1.timestamp }

        guard validPoints.count >= 2 else { return [] }

        var segments: [TrajectorySegment] = []
        var currentPoints: [TrajectoryPoint] = [validPoints[0]]

        for i in 1..<validPoints.count {
            let prev = currentPoints.last!
            let curr = validPoints[i]

            let dt = curr.timestamp.timeIntervalSince(prev.timestamp)
            let dist = haversineDistance(from: prev, to: curr)

            let isNonpositiveDelta = dt <= 0.0
            let isTimeGap = dt > maxTimeGapSeconds
            let isDistanceJump = dist > maxDistanceMeters
            let isSpeedExceeded = dt > 0.0 && (dist / dt) > maxSpeedMetersPerSecond

            if isNonpositiveDelta || isTimeGap || isDistanceJump || isSpeedExceeded {
                if currentPoints.count >= 2 {
                    segments.append(TrajectorySegment(points: currentPoints))
                }
                currentPoints = [curr]
            } else {
                currentPoints.append(curr)
            }
        }

        if currentPoints.count >= 2 {
            segments.append(TrajectorySegment(points: currentPoints))
        }

        return segments
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
    ///
    /// Performance note: Linear pass over the polyline segments (O(N)). For a single day's
    /// trajectory points (typically hundreds to low thousands), execution completes in <1ms.
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
