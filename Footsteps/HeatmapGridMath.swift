import Foundation

struct DensityCell: Equatable {
    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double
    let count: Int
    let intensity: Double

    init(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double, count: Int, intensity: Double) {
        self.minLat = minLat
        self.maxLat = maxLat
        self.minLon = minLon
        self.maxLon = maxLon
        self.count = count
        self.intensity = intensity
    }
}

enum HeatmapGridMath {
    static let defaultCellSizeDegrees: Double = 0.001

    static func isValid(latitude: Double, longitude: Double, horizontalAccuracy: Double) -> Bool {
        guard latitude.isFinite, longitude.isFinite, horizontalAccuracy.isFinite else { return false }
        guard latitude >= -90.0 && latitude <= 90.0 else { return false }
        guard longitude >= -180.0 && longitude <= 180.0 else { return false }
        guard horizontalAccuracy >= 0.0 else { return false }
        return true
    }

    static func dayInterval(for date: Date, calendar: Calendar = .current) -> DateInterval {
        let startOfDay = calendar.startOfDay(for: date)
        let nextStartOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(86400)
        return DateInterval(start: startOfDay, end: nextStartOfDay)
    }

    static func isToday(_ date: Date, calendar: Calendar = .current, now: Date = Date()) -> Bool {
        calendar.isDate(date, inSameDayAs: now)
    }

    static func canNavigateNext(from date: Date, calendar: Calendar = .current, now: Date = Date()) -> Bool {
        let startOfDate = calendar.startOfDay(for: date)
        let startOfToday = calendar.startOfDay(for: now)
        return startOfDate < startOfToday
    }

    static func previousDay(from date: Date, calendar: Calendar = .current) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: -1, to: startOfDay) ?? startOfDay.addingTimeInterval(-86400)
    }

    static func nextDay(from date: Date, calendar: Calendar = .current) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(86400)
    }

    static func computeDensityGrid(
        coordinates: [(latitude: Double, longitude: Double)],
        cellSizeDegrees: Double = defaultCellSizeDegrees
    ) -> [DensityCell] {
        guard !coordinates.isEmpty else { return [] }
        guard cellSizeDegrees.isFinite, cellSizeDegrees > 0 else { return [] }

        var cellCounts: [String: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double, count: Int)] = [:]
        for coord in coordinates {
            guard isValid(latitude: coord.latitude, longitude: coord.longitude, horizontalAccuracy: 0.0) else { continue }
            let latIndex = Int(floor(coord.latitude / cellSizeDegrees))
            let lonIndex = Int(floor(coord.longitude / cellSizeDegrees))
            let key = "\(latIndex),\(lonIndex)"
            if var existing = cellCounts[key] {
                existing.count += 1
                cellCounts[key] = existing
            } else {
                let rawMinLat = Double(latIndex) * cellSizeDegrees
                let rawMaxLat = rawMinLat + cellSizeDegrees
                let minLat = max(-90.0, min(90.0, rawMinLat))
                let maxLat = max(-90.0, min(90.0, rawMaxLat))

                let rawMinLon = Double(lonIndex) * cellSizeDegrees
                let rawMaxLon = rawMinLon + cellSizeDegrees
                let minLon = max(-180.0, min(180.0, rawMinLon))
                let maxLon = max(-180.0, min(180.0, rawMaxLon))

                cellCounts[key] = (minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon, count: 1)
            }
        }
        guard !cellCounts.isEmpty else { return [] }
        let maxCount = cellCounts.values.map(\.count).max() ?? 1
        return cellCounts.values.map { cell in
            let intensity = maxCount > 0 ? Double(cell.count) / Double(maxCount) : 1.0
            return DensityCell(
                minLat: cell.minLat,
                maxLat: cell.maxLat,
                minLon: cell.minLon,
                maxLon: cell.maxLon,
                count: cell.count,
                intensity: intensity
            )
        }
    }
}
