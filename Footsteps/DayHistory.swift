import Foundation

/// A single supported stationary dwell episode at a geographical location.
public struct DayStay: Identifiable, Equatable, Sendable {
    public let id: String
    public let latitude: Double
    public let longitude: Double
    public let arrivalDate: Date
    public let departureDate: Date
    public let duration: TimeInterval
    public let horizontalAccuracy: Double
    public let anchorRadius: Double
    public var assignedPlaceID: String?
    public var assignedPlaceLabel: String?

    public init(
        id: String,
        latitude: Double,
        longitude: Double,
        arrivalDate: Date,
        departureDate: Date,
        duration: TimeInterval,
        horizontalAccuracy: Double,
        anchorRadius: Double = 25.0,
        assignedPlaceID: String? = nil,
        assignedPlaceLabel: String? = nil
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.arrivalDate = arrivalDate
        self.departureDate = departureDate
        self.duration = duration
        self.horizontalAccuracy = horizontalAccuracy
        self.anchorRadius = anchorRadius
        self.assignedPlaceID = assignedPlaceID
        self.assignedPlaceLabel = assignedPlaceLabel
    }
}

/// A conservatively clustered geographical place visited one or more times during a day.
public struct DayPlace: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let latitude: Double
    public let longitude: Double
    public let totalDuration: TimeInterval
    public let visitCount: Int
    public let firstArrival: Date
    public let lastDeparture: Date

    public init(
        id: String,
        label: String,
        latitude: Double,
        longitude: Double,
        totalDuration: TimeInterval,
        visitCount: Int,
        firstArrival: Date,
        lastDeparture: Date
    ) {
        self.id = id
        self.label = label
        self.latitude = latitude
        self.longitude = longitude
        self.totalDuration = totalDuration
        self.visitCount = visitCount
        self.firstArrival = firstArrival
        self.lastDeparture = lastDeparture
    }
}

/// A point along the cumulative observed distance progression of a day.
public struct CumulativeDistancePoint: Identifiable, Equatable, Sendable {
    public let id: String
    public let timestamp: Date
    public let distanceMeters: Double

    public init(id: String = UUID().uuidString, timestamp: Date, distanceMeters: Double) {
        self.id = id
        self.timestamp = timestamp
        self.distanceMeters = distanceMeters
    }
}

/// Complete derived historical model for a specific calendar day.
public struct DayHistory: Equatable, Sendable {
    public let selectedDate: Date
    public let dayInterval: DateInterval
    public let totalElapsedDuration: TimeInterval
    public let movingDuration: TimeInterval
    public let stationaryDuration: TimeInterval
    public let unknownDuration: TimeInterval
    public let observedDistanceMeters: Double
    public let movingSegments: [TrajectorySegment]
    public let stays: [DayStay]
    public let singleObservations: [TrajectoryPoint]
    public let places: [DayPlace]
    public let cumulativeDistanceSeries: [[CumulativeDistancePoint]]
    public let movingIntervals: [DateInterval]
    public let stationaryIntervals: [DateInterval]
    public let unknownIntervals: [DateInterval]

    public init(
        selectedDate: Date,
        dayInterval: DateInterval,
        totalElapsedDuration: TimeInterval,
        movingDuration: TimeInterval,
        stationaryDuration: TimeInterval,
        unknownDuration: TimeInterval,
        observedDistanceMeters: Double,
        movingSegments: [TrajectorySegment],
        stays: [DayStay],
        singleObservations: [TrajectoryPoint],
        places: [DayPlace],
        cumulativeDistanceSeries: [[CumulativeDistancePoint]],
        movingIntervals: [DateInterval],
        stationaryIntervals: [DateInterval],
        unknownIntervals: [DateInterval]
    ) {
        self.selectedDate = selectedDate
        self.dayInterval = dayInterval
        self.totalElapsedDuration = totalElapsedDuration
        self.movingDuration = movingDuration
        self.stationaryDuration = stationaryDuration
        self.unknownDuration = unknownDuration
        self.observedDistanceMeters = observedDistanceMeters
        self.movingSegments = movingSegments
        self.stays = stays
        self.singleObservations = singleObservations
        self.places = places
        self.cumulativeDistanceSeries = cumulativeDistanceSeries
        self.movingIntervals = movingIntervals
        self.stationaryIntervals = stationaryIntervals
        self.unknownIntervals = unknownIntervals
    }

    // MARK: - Construction Factory

    public static func build(
        points: [TrajectoryPoint],
        selectedDate: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DayHistory {
        let interval = TrajectoryMath.dayInterval(for: selectedDate, calendar: calendar)
        let startOfDay = interval.start
        let endOfDay = interval.end

        // 1. Calculate day total elapsed duration
        let totalElapsedDuration: TimeInterval
        let effectiveEnd: Date

        if startOfDay >= now {
            // Future day: 0 elapsed time
            totalElapsedDuration = 0.0
            effectiveEnd = startOfDay
        } else if now < endOfDay {
            // Today: only time elapsed up to now
            effectiveEnd = now
            totalElapsedDuration = max(0.0, effectiveEnd.timeIntervalSince(startOfDay))
        } else {
            // Past day: full day span (accounts for 23h spring DST, 25h fall DST, 24h normal)
            effectiveEnd = endOfDay
            totalElapsedDuration = max(0.0, effectiveEnd.timeIntervalSince(startOfDay))
        }

        guard totalElapsedDuration > 0.0 else {
            return DayHistory(
                selectedDate: selectedDate,
                dayInterval: interval,
                totalElapsedDuration: 0.0,
                movingDuration: 0.0,
                stationaryDuration: 0.0,
                unknownDuration: 0.0,
                observedDistanceMeters: 0.0,
                movingSegments: [],
                stays: [],
                singleObservations: [],
                places: [],
                cumulativeDistanceSeries: [],
                movingIntervals: [],
                stationaryIntervals: [],
                unknownIntervals: []
            )
        }

        // 2. Filter raw points to the query interval [startOfDay, effectiveEnd)
        let dayPoints = points.filter { $0.timestamp >= startOfDay && $0.timestamp < effectiveEnd }

        // 3. Segment and analyze trajectory
        let analysis = TrajectoryMath.analyzeDay(points: dayPoints)

        // 4. Extract moving segments and stationary stays
        let movingSegments = analysis.segments
        var stays: [DayStay] = []
        var singleObservations: [TrajectoryPoint] = []

        for singleton in analysis.singletons {
            if singleton.observationDuration > 0 {
                let arr = singleton.point.timestamp
                let dep = arr.addingTimeInterval(singleton.observationDuration)
                let stay = DayStay(
                    id: singleton.id,
                    latitude: singleton.point.latitude,
                    longitude: singleton.point.longitude,
                    arrivalDate: arr,
                    departureDate: min(dep, effectiveEnd),
                    duration: singleton.observationDuration,
                    horizontalAccuracy: singleton.point.horizontalAccuracy,
                    anchorRadius: max(singleton.point.horizontalAccuracy, 15.0)
                )
                stays.append(stay)
            } else {
                singleObservations.append(singleton.point)
            }
        }

        // 5. Build non-overlapping moving and stationary intervals
        var rawMovingIntervals: [DateInterval] = []
        for seg in movingSegments {
            if seg.startDate < seg.endDate {
                rawMovingIntervals.append(DateInterval(start: seg.startDate, end: seg.endDate))
            }
        }

        var rawStationaryIntervals: [DateInterval] = []
        for stay in stays {
            if stay.arrivalDate < stay.departureDate {
                rawStationaryIntervals.append(DateInterval(start: stay.arrivalDate, end: stay.departureDate))
            }
        }

        let movingIntervals = mergeIntervals(rawMovingIntervals)
        let stationaryIntervals = mergeIntervals(rawStationaryIntervals)

        let movingDuration = movingIntervals.reduce(0.0) { $0 + $1.duration }
        let stationaryDuration = stationaryIntervals.reduce(0.0) { $0 + $1.duration }

        // Compute unknown intervals as the complement of (moving ∪ stationary) over [startOfDay, effectiveEnd]
        let occupiedIntervals = mergeIntervals(movingIntervals + stationaryIntervals)
        let unknownIntervals = complementIntervals(
            occupied: occupiedIntervals,
            domain: DateInterval(start: startOfDay, end: effectiveEnd)
        )
        let unknownDuration = unknownIntervals.reduce(0.0) { $0 + $1.duration }

        // 6. Calculate total observed distance (from moving segments only)
        let observedDistanceMeters = movingSegments.reduce(0.0) { $0 + $1.distanceMeters }

        // 7. Conservative deterministic place grouping (<= 65 meters)
        let (clusteredPlaces, updatedStays) = groupStaysIntoPlaces(stays: stays)

        // 8. Build disjoint cumulative distance series
        let cumulativeSeries = buildCumulativeDistanceSeries(
            movingSegments: movingSegments,
            stays: updatedStays,
            startOfDay: startOfDay,
            effectiveEnd: effectiveEnd
        )

        return DayHistory(
            selectedDate: selectedDate,
            dayInterval: interval,
            totalElapsedDuration: totalElapsedDuration,
            movingDuration: movingDuration,
            stationaryDuration: stationaryDuration,
            unknownDuration: unknownDuration,
            observedDistanceMeters: observedDistanceMeters,
            movingSegments: movingSegments,
            stays: updatedStays,
            singleObservations: singleObservations,
            places: clusteredPlaces,
            cumulativeDistanceSeries: cumulativeSeries,
            movingIntervals: movingIntervals,
            stationaryIntervals: stationaryIntervals,
            unknownIntervals: unknownIntervals
        )
    }

    // MARK: - Interval Math Helpers

    /// Merges overlapping or touching date intervals into a minimal sorted list of disjoint intervals.
    public static func mergeIntervals(_ intervals: [DateInterval]) -> [DateInterval] {
        guard !intervals.isEmpty else { return [] }
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [DateInterval] = []

        var current = sorted[0]
        for i in 1..<sorted.count {
            let next = sorted[i]
            if next.start <= current.end {
                // Overlaps or touches: extend current end
                if next.end > current.end {
                    current = DateInterval(start: current.start, end: next.end)
                }
            } else {
                merged.append(current)
                current = next
            }
        }
        merged.append(current)
        return merged
    }

    /// Computes the exact complement of occupied intervals within a bounded domain interval.
    public static func complementIntervals(occupied: [DateInterval], domain: DateInterval) -> [DateInterval] {
        guard domain.duration > 0 else { return [] }
        let mergedOccupied = mergeIntervals(occupied)
        var complement: [DateInterval] = []

        var cursor = domain.start

        for interval in mergedOccupied {
            // Clip occupied interval to domain
            let occStart = max(domain.start, min(domain.end, interval.start))
            let occEnd = max(domain.start, min(domain.end, interval.end))

            if occStart > cursor {
                complement.append(DateInterval(start: cursor, end: occStart))
            }
            if occEnd > cursor {
                cursor = occEnd
            }
        }

        if cursor < domain.end {
            complement.append(DateInterval(start: cursor, end: domain.end))
        }

        return complement
    }

    // MARK: - Conservative Place Clustering

    /// Groups stays into conservative, deterministically numbered places using anchored proximity.
    private static func groupStaysIntoPlaces(
        stays: [DayStay],
        proximityThresholdMeters: Double = 65.0
    ) -> (places: [DayPlace], updatedStays: [DayStay]) {
        guard !stays.isEmpty else { return ([], []) }

        var placeAnchors: [(id: String, label: String, lat: Double, lon: Double, stays: [DayStay])] = []
        var updatedStays: [DayStay] = []

        // Process stays chronologically
        let sortedStays = stays.sorted { $0.arrivalDate < $1.arrivalDate }

        for stay in sortedStays {
            var matchedIndex: Int? = nil
            for i in 0..<placeAnchors.count {
                let dist = TrajectoryMath.haversineDistance(
                    lat1: placeAnchors[i].lat,
                    lon1: placeAnchors[i].lon,
                    lat2: stay.latitude,
                    lon2: stay.longitude
                )
                if dist <= proximityThresholdMeters {
                    matchedIndex = i
                    break
                }
            }

            let placeID: String
            let placeLabel: String

            if let idx = matchedIndex {
                placeID = placeAnchors[idx].id
                placeLabel = placeAnchors[idx].label
                placeAnchors[idx].stays.append(stay)
            } else {
                let newIndex = placeAnchors.count + 1
                placeID = "place_\(newIndex)"
                placeLabel = "Place \(newIndex)"
                placeAnchors.append((
                    id: placeID,
                    label: placeLabel,
                    lat: stay.latitude,
                    lon: stay.longitude,
                    stays: [stay]
                ))
            }

            var stayCopy = stay
            stayCopy.assignedPlaceID = placeID
            stayCopy.assignedPlaceLabel = placeLabel
            updatedStays.append(stayCopy)
        }

        let places: [DayPlace] = placeAnchors.map { anchor in
            let totalDur = anchor.stays.reduce(0.0) { $0 + $1.duration }
            let firstArr = anchor.stays.map(\.arrivalDate).min() ?? Date()
            let lastDep = anchor.stays.map(\.departureDate).max() ?? Date()
            return DayPlace(
                id: anchor.id,
                label: anchor.label,
                latitude: anchor.lat,
                longitude: anchor.lon,
                totalDuration: totalDur,
                visitCount: anchor.stays.count,
                firstArrival: firstArr,
                lastDeparture: lastDep
            )
        }

        return (places, updatedStays)
    }

    // MARK: - Cumulative Distance Disjoint Series

    private static func buildCumulativeDistanceSeries(
        movingSegments: [TrajectorySegment],
        stays: [DayStay],
        startOfDay: Date,
        effectiveEnd: Date
    ) -> [[CumulativeDistancePoint]] {
        // Collect moving segments and stays as timed episodes
        enum Episode {
            case moving(TrajectorySegment)
            case stay(DayStay)

            var startDate: Date {
                switch self {
                case .moving(let seg): return seg.startDate
                case .stay(let st): return st.arrivalDate
                }
            }

            var endDate: Date {
                switch self {
                case .moving(let seg): return seg.endDate
                case .stay(let st): return st.departureDate
                }
            }
        }

        var episodes: [Episode] = []
        for seg in movingSegments {
            episodes.append(.moving(seg))
        }
        for stay in stays {
            episodes.append(.stay(stay))
        }
        episodes.sort { $0.startDate < $1.startDate }

        guard !episodes.isEmpty else { return [] }

        var seriesList: [[CumulativeDistancePoint]] = []
        var currentSeries: [CumulativeDistancePoint] = []
        var runningDistance: Double = 0.0

        for i in 0..<episodes.count {
            let ep = episodes[i]

            // Check if there is an unknown gap before this episode
            if i > 0 {
                let prevEnd = episodes[i - 1].endDate
                let dt = ep.startDate.timeIntervalSince(prevEnd)
                if dt > TrajectoryMath.defaultMaxTimeGapSeconds {
                    // Break series across unknown gap
                    if !currentSeries.isEmpty {
                        seriesList.append(currentSeries)
                        currentSeries = []
                    }
                }
            }

            switch ep {
            case .moving(let seg):
                for i in 0..<seg.points.count {
                    let pt = seg.points[i]
                    if i > 0 {
                        let segDist = TrajectoryMath.haversineDistance(
                            from: seg.points[i - 1],
                            to: pt
                        )
                        runningDistance += segDist
                    }
                    currentSeries.append(CumulativeDistancePoint(
                        timestamp: pt.timestamp,
                        distanceMeters: runningDistance
                    ))
                }
            case .stay(let st):
                // Stay renders as flat cumulative distance from arrival to departure
                currentSeries.append(CumulativeDistancePoint(
                    timestamp: st.arrivalDate,
                    distanceMeters: runningDistance
                ))
                currentSeries.append(CumulativeDistancePoint(
                    timestamp: st.departureDate,
                    distanceMeters: runningDistance
                ))
            }
        }

        if !currentSeries.isEmpty {
            seriesList.append(currentSeries)
        }

        return seriesList
    }

    // MARK: - Presentation Formatting Helpers

    public static func formatObservedBounds(start: Date, end: Date) -> String {
        let startStr = start.formatted(date: .omitted, time: .shortened)
        let endStr = end.formatted(date: .omitted, time: .shortened)
        if startStr == endStr {
            return "Observed at \(startStr)"
        }
        return "Observed \(startStr) – \(endStr)"
    }

    public static func formatDistance(_ meters: Double) -> String {
        if meters >= 1000.0 {
            return String(format: "%.1f km", meters / 1000.0)
        } else {
            return String(format: "%.0f m", meters)
        }
    }

    public static func formatDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds / 60.0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(hours)h"
            }
        } else if minutes > 0 {
            return "\(minutes)m"
        } else if seconds > 0 {
            return "< 1m"
        } else {
            return "0m"
        }
    }
}
