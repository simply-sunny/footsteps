import Foundation
import SwiftData

public enum LocationSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [LocationPoint.self]
    }

    @Model
    public final class LocationPoint {
        public var latitude: Double
        public var longitude: Double
        public var timestamp: Date
        public var horizontalAccuracy: Double

        public init(
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
}

public enum LocationSchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version = Schema.Version(2, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [LocationPoint.self]
    }

    @Model
    public final class LocationPoint {
        public var latitude: Double
        public var longitude: Double
        public var timestamp: Date
        public var horizontalAccuracy: Double

        // Auxiliary CoreLocation metrics (optional, preserving raw reported values including sentinels)
        public var altitude: Double?
        public var verticalAccuracy: Double?
        public var speed: Double?
        public var speedAccuracy: Double?
        public var course: Double?
        public var courseAccuracy: Double?
        public var floor: Int?
        public var sourceProvider: String?

        // iOS 15+ CoreLocation source information flags
        public var isSimulatedBySoftware: Bool?
        public var isProducedByAccessory: Bool?

        // Ingestion & Lifecycle diagnostics
        public var receivedTimestamp: Date = Date()
        public var sessionID: String = ""
        public var isBackground: Bool? = nil

        public init(
            latitude: Double,
            longitude: Double,
            timestamp: Date = Date(),
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
            receivedTimestamp: Date = Date(),
            sessionID: String = "",
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
}

public enum LocationMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [LocationSchemaV1.self, LocationSchemaV2.self]
    }

    public static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    public static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: LocationSchemaV1.self,
        toVersion: LocationSchemaV2.self
    )
}

public typealias LocationPoint = LocationSchemaV2.LocationPoint
