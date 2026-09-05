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
                let minLat = Double(latIndex) * cellSizeDegrees
                let maxLat = minLat + cellSizeDegrees
                let minLon = Double(lonIndex) * cellSizeDegrees
                let maxLon = minLon + cellSizeDegrees
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
