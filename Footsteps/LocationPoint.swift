import Foundation
import SwiftData

@Model
final class LocationPoint {
    var latitude: Double
    var longitude: Double
    var timestamp: Date
    var horizontalAccuracy: Double

    init(
        latitude: Double,
        longitude: Double,
        timestamp: Date = Date(),
        horizontalAccuracy: Double = 0.0
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.horizontalAccuracy = horizontalAccuracy
    }
}
