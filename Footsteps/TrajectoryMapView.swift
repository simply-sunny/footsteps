import SwiftUI
import MapKit

/// Display mode for the primary map view.
public enum MapDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case path = "Path"
    case time = "Time"

    public var id: String { rawValue }
}

/// Status classification of an individual location fix for developer diagnostic rendering.
public enum DebugPointStatus: String, Sendable {
    case usable = "Usable (≤100m)"
    case suspicious = "Suspicious (100–200m)"
    case outlier = "Outlier (>200m / Invalid)"
}

/// MKPolyline subclass carrying a deterministic segment identifier.
public final class SegmentPolyline: MKPolyline {
    public var segmentID: String = ""

    public static func create(from segment: TrajectorySegment) -> SegmentPolyline {
        let coords = segment.points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        let polyline = SegmentPolyline(coordinates: coords, count: coords.count)
        polyline.segmentID = segment.id
        return polyline
    }
}

/// MKCircle subclass representing a supported stationary dwell episode.
public final class StayCircleOverlay: MKCircle {
    public var stayID: String = ""
    public var stay: DayStay?

    public static func create(from stay: DayStay) -> StayCircleOverlay {
        let coord = CLLocationCoordinate2D(latitude: stay.latitude, longitude: stay.longitude)
        // Scaled radius based on duration (15m to 65m)
        let durationMinutes = max(1.0, stay.duration / 60.0)
        let radius = max(15.0, min(65.0, 15.0 + 8.0 * log2(durationMinutes)))
        let circle = StayCircleOverlay(center: coord, radius: radius)
        circle.stayID = stay.id
        circle.stay = stay
        return circle
    }
}

/// MKCircle subclass representing an isolated fix without inferred stay duration.
public final class SingleObservationOverlay: MKCircle {
    public var pointID: String = ""
    public var point: TrajectoryPoint?

    public static func create(from point: TrajectoryPoint) -> SingleObservationOverlay {
        let coord = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
        let circle = SingleObservationOverlay(center: coord, radius: max(8.0, point.horizontalAccuracy))
        let tsMs = Int64(point.timestamp.timeIntervalSince1970 * 1000)
        circle.pointID = "obs_\(tsMs)"
        circle.point = point
        return circle
    }
}

/// MKCircle subclass for time-weighted heat rendering in Time mode.
public final class DwellHeatOverlay: MKCircle {
    public var stayID: String = ""
    public var stay: DayStay?
    public var durationSeconds: TimeInterval = 0.0

    public static func create(from stay: DayStay) -> DwellHeatOverlay {
        let coord = CLLocationCoordinate2D(latitude: stay.latitude, longitude: stay.longitude)
        let durationMinutes = max(1.0, stay.duration / 60.0)
        // Smooth radial spread proportional to sqrt(duration)
        let radius = max(25.0, min(150.0, 20.0 + 4.0 * sqrt(durationMinutes)))
        let circle = DwellHeatOverlay(center: coord, radius: radius)
        circle.stayID = stay.id
        circle.stay = stay
        circle.durationSeconds = stay.duration
        return circle
    }
}

/// Custom MKOverlayRenderer producing smooth time-weighted radial heat gradients.
public final class DwellHeatRenderer: MKOverlayRenderer {
    public var isSelected: Bool = false

    public override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let heatOverlay = overlay as? DwellHeatOverlay else { return }

        let centerMapPoint = MKMapPoint(heatOverlay.coordinate)
        let centerPoint = point(for: centerMapPoint)
        let radiusMapPoints = heatOverlay.radius * MKMapPointsPerMeterAtLatitude(heatOverlay.coordinate.latitude)
        let renderRadius = CGFloat(radiusMapPoints * Double(zoomScale))

        guard renderRadius > 0 else { return }

        context.saveGState()

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let durationHours = heatOverlay.durationSeconds / 3600.0

        let centerColor: UIColor
        let midColor: UIColor

        if isSelected {
            centerColor = UIColor.systemOrange.withAlphaComponent(0.85)
            midColor = UIColor.systemYellow.withAlphaComponent(0.45)
        } else if durationHours >= 2.0 {
            // Intense dwell (>= 2h): deep orange-red core
            centerColor = UIColor.systemOrange.withAlphaComponent(0.70)
            midColor = UIColor.systemYellow.withAlphaComponent(0.35)
        } else {
            // Moderate dwell (< 2h): warm amber core
            centerColor = UIColor.systemYellow.withAlphaComponent(0.65)
            midColor = UIColor.systemYellow.withAlphaComponent(0.25)
        }

        let colors = [
            centerColor.cgColor,
            midColor.cgColor,
            UIColor.clear.cgColor
        ] as CFArray

        let locations: [CGFloat] = [0.0, 0.5, 1.0]

        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
            context.drawRadialGradient(
                gradient,
                startCenter: centerPoint,
                startRadius: 0.0,
                endCenter: centerPoint,
                endRadius: renderRadius,
                options: .drawsAfterEndLocation
            )
        }

        context.restoreGState()
    }
}

/// MKCircle subclass for developer diagnostic raw point overlay.
public final class DebugPointCircleOverlay: MKCircle {
    public var pointID: String = ""
    public var point: TrajectoryPoint?
    public var status: DebugPointStatus = .usable
    public var gapFromPrevious: TimeInterval?

    public static func create(
        from point: TrajectoryPoint,
        status: DebugPointStatus,
        gapFromPrevious: TimeInterval? = nil
    ) -> DebugPointCircleOverlay {
        let coord = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
        let radius = max(6.0, point.horizontalAccuracy)
        let circle = DebugPointCircleOverlay(center: coord, radius: radius)
        let tsMs = Int64(point.timestamp.timeIntervalSince1970 * 1000)
        let lat = String(format: "%.5f", point.latitude)
        let lon = String(format: "%.5f", point.longitude)
        circle.pointID = "raw_\(tsMs)_\(lat)_\(lon)"
        circle.point = point
        circle.status = status
        circle.gapFromPrevious = gapFromPrevious
        return circle
    }
}

/// Legacy bridge for TrajectorySingleton overlay support.
public final class SingletonCircleOverlay: MKCircle {
    public var singletonID: String = ""

    public static func create(from singleton: TrajectorySingleton) -> SingletonCircleOverlay {
        let coord = CLLocationCoordinate2D(latitude: singleton.point.latitude, longitude: singleton.point.longitude)
        let radius = max(10.0, singleton.point.horizontalAccuracy)
        let circle = SingletonCircleOverlay(center: coord, radius: radius)
        circle.singletonID = singleton.id
        return circle
    }
}

/// SwiftUI wrapper for MKMapView supporting Path and Time modes, dwell heat rendering, and tap hit-testing.
public struct TrajectoryMapView: UIViewRepresentable {
    public let segments: [TrajectorySegment]
    public let stays: [DayStay]
    public let singleObservations: [TrajectoryPoint]
    public let singletons: [TrajectorySingleton]
    public let rawPoints: [TrajectoryPoint]
    public let displayMode: MapDisplayMode
    public let showDebugOverlay: Bool
    public let dayKey: String
    public let recenterTrigger: Int
    @Binding public var selectedItemID: String?

    public init(
        segments: [TrajectorySegment] = [],
        stays: [DayStay] = [],
        singleObservations: [TrajectoryPoint] = [],
        singletons: [TrajectorySingleton] = [],
        rawPoints: [TrajectoryPoint] = [],
        displayMode: MapDisplayMode = .path,
        showDebugOverlay: Bool = false,
        dayKey: String = "",
        recenterTrigger: Int = 0,
        selectedItemID: Binding<String?> = .constant(nil)
    ) {
        self.segments = segments
        self.stays = stays
        self.singleObservations = singleObservations
        self.singletons = singletons
        self.rawPoints = rawPoints
        self.displayMode = displayMode
        self.showDebugOverlay = showDebugOverlay
        self.dayKey = dayKey
        self.recenterTrigger = recenterTrigger
        self._selectedItemID = selectedItemID
    }

    public init(
        segments: [TrajectorySegment],
        singletons: [TrajectorySingleton] = [],
        rawPoints: [TrajectoryPoint] = [],
        showDebugOverlay: Bool = false,
        dayKey: String = "",
        selectedSegmentID: Binding<String?> = .constant(nil)
    ) {
        self.segments = segments
        self.stays = []
        self.singleObservations = []
        self.singletons = singletons
        self.rawPoints = rawPoints
        self.displayMode = .path
        self.showDebugOverlay = showDebugOverlay
        self.dayKey = dayKey
        self.recenterTrigger = 0
        self._selectedItemID = selectedSegmentID
    }

    public func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = false

        // Tap gesture for forgiving hit testing
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMapTap(_:))
        )
        mapView.addGestureRecognizer(tapGesture)

        return mapView
    }

    public func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onSelectItem = { newSelectedID in
            DispatchQueue.main.async {
                self.selectedItemID = newSelectedID
            }
        }

        let didRecenter = (coordinator.lastRecenterTrigger != recenterTrigger)
        if didRecenter {
            coordinator.lastRecenterTrigger = recenterTrigger
        }

        // Bridge legacy singletons if stays are empty
        let effectiveStays: [DayStay]
        let effectiveSingleObs: [TrajectoryPoint]
        if stays.isEmpty && !singletons.isEmpty {
            effectiveStays = singletons.compactMap { s in
                guard s.observationDuration > 0 else { return nil }
                return DayStay(
                    id: s.id,
                    latitude: s.point.latitude,
                    longitude: s.point.longitude,
                    arrivalDate: s.point.timestamp,
                    departureDate: s.point.timestamp.addingTimeInterval(s.observationDuration),
                    duration: s.observationDuration,
                    horizontalAccuracy: s.point.horizontalAccuracy
                )
            }
            effectiveSingleObs = singletons.compactMap { s in
                guard s.observationDuration == 0 else { return nil }
                return s.point
            }
        } else {
            effectiveStays = stays
            effectiveSingleObs = singleObservations
        }

        _ = coordinator.updateMapOverlays(
            mapView: mapView,
            segments: segments,
            stays: effectiveStays,
            singleObservations: effectiveSingleObs,
            rawPoints: rawPoints,
            showDebugOverlay: showDebugOverlay,
            displayMode: displayMode,
            dayKey: dayKey,
            forceRecenter: didRecenter
        )

        if selectedItemID != coordinator.selectedItemID {
            coordinator.selectedItemID = selectedItemID
            coordinator.refreshSelectionRendering(mapView: mapView)
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public final class Coordinator: NSObject, MKMapViewDelegate {
        public var segments: [TrajectorySegment] = []
        public var stays: [DayStay] = []
        public var singleObservations: [TrajectoryPoint] = []
        public var singletons: [TrajectorySingleton] = []
        public var debugOverlays: [DebugPointCircleOverlay] = []
        public var selectedItemID: String? = nil
        public var lastRenderedDayKey: String? = nil
        public var lastRenderedSignature: String = ""
        public var lastRecenterTrigger: Int = 0
        public var onSelectItem: ((String?) -> Void)?

        // Backward compatibility properties
        public var selectedSegmentID: String? {
            get { selectedItemID }
            set { selectedItemID = newValue }
        }
        public var onSelectSegment: ((String?) -> Void)? {
            get { onSelectItem }
            set { onSelectItem = newValue }
        }

        // Legacy compatibility overload
        public func updateMapOverlays(
            mapView: MKMapView,
            segments: [TrajectorySegment],
            singletons: [TrajectorySingleton] = [],
            rawPoints: [TrajectoryPoint] = [],
            showDebugOverlay: Bool = false,
            dayKey: String
        ) -> Bool {
            let bridgedStays = singletons.compactMap { s -> DayStay? in
                guard s.observationDuration > 0 else { return nil }
                return DayStay(
                    id: s.id,
                    latitude: s.point.latitude,
                    longitude: s.point.longitude,
                    arrivalDate: s.point.timestamp,
                    departureDate: s.point.timestamp.addingTimeInterval(s.observationDuration),
                    duration: s.observationDuration,
                    horizontalAccuracy: s.point.horizontalAccuracy
                )
            }
            let bridgedSingleObs = singletons.compactMap { s -> TrajectoryPoint? in
                guard s.observationDuration == 0 else { return nil }
                return s.point
            }
            return updateMapOverlays(
                mapView: mapView,
                segments: segments,
                stays: bridgedStays,
                singleObservations: bridgedSingleObs,
                rawPoints: rawPoints,
                showDebugOverlay: showDebugOverlay,
                displayMode: .path,
                dayKey: dayKey
            )
        }

        public func updateMapOverlays(
            mapView: MKMapView,
            segments: [TrajectorySegment],
            stays: [DayStay] = [],
            singleObservations: [TrajectoryPoint] = [],
            rawPoints: [TrajectoryPoint] = [],
            showDebugOverlay: Bool = false,
            displayMode: MapDisplayMode = .path,
            dayKey: String,
            forceRecenter: Bool = false
        ) -> Bool {
            let dayChanged = (lastRenderedDayKey != dayKey)
            let signature = "\(dayKey)_\(displayMode.rawValue)_\(showDebugOverlay)_\(segments.count)_\(stays.count)_\(singleObservations.count)_\(rawPoints.count)"

            guard signature != lastRenderedSignature || dayChanged || forceRecenter else {
                return false
            }

            lastRenderedSignature = signature
            self.segments = segments
            self.stays = stays
            self.singleObservations = singleObservations
            self.debugOverlays = []

            mapView.removeOverlays(mapView.overlays)

            if displayMode == .path {
                for segment in segments {
                    let polyline = SegmentPolyline.create(from: segment)
                    mapView.addOverlay(polyline)
                }

                for stay in stays {
                    let circle = StayCircleOverlay.create(from: stay)
                    mapView.addOverlay(circle)
                }
            } else if displayMode == .time {
                for stay in stays {
                    let heatCircle = DwellHeatOverlay.create(from: stay)
                    mapView.addOverlay(heatCircle)
                }
            }

            for obs in singleObservations {
                let obsCircle = SingleObservationOverlay.create(from: obs)
                mapView.addOverlay(obsCircle)
            }

            if showDebugOverlay {
                let sorted = rawPoints.sorted { $0.timestamp < $1.timestamp }
                for i in 0..<sorted.count {
                    let pt = sorted[i]
                    let status: DebugPointStatus
                    if !TrajectoryMath.isValid(point: pt, maxHorizontalAccuracy: TrajectoryMath.defaultMaxHorizontalAccuracy) {
                        status = .outlier
                    } else if pt.horizontalAccuracy > TrajectoryMath.defaultSuspiciousAccuracyThreshold {
                        status = .suspicious
                    } else {
                        status = .usable
                    }
                    let gap: TimeInterval? = (i > 0) ? pt.timestamp.timeIntervalSince(sorted[i - 1].timestamp) : nil
                    let debugCircle = DebugPointCircleOverlay.create(from: pt, status: status, gapFromPrevious: gap)
                    self.debugOverlays.append(debugCircle)
                    mapView.addOverlay(debugCircle)
                }
            }

            var didFrame = false
            if dayChanged || forceRecenter {
                lastRenderedDayKey = dayKey
                if let firstRect = mapView.overlays.first?.boundingMapRect {
                    let unionRect = mapView.overlays.reduce(firstRect) { $0.union($1.boundingMapRect) }
                    if !unionRect.isNull && unionRect.size.width > 0 && unionRect.size.height > 0 {
                        let padding = UIEdgeInsets(top: 80, left: 40, bottom: 120, right: 40)
                        mapView.setVisibleMapRect(unionRect, edgePadding: padding, animated: true)
                        didFrame = true
                    }
                } else if let userCoord = mapView.userLocation.location?.coordinate {
                    let region = MKCoordinateRegion(
                        center: userCoord,
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    )
                    mapView.setRegion(region, animated: true)
                    didFrame = true
                } else {
                    didFrame = true
                }
            }

            return didFrame
        }

        public func refreshSelectionRendering(mapView: MKMapView) {
            for overlay in mapView.overlays {
                if let renderer = mapView.renderer(for: overlay) as? MKPolylineRenderer {
                    let isSelected = (overlay as? SegmentPolyline)?.segmentID == selectedItemID
                    renderer.strokeColor = isSelected ? UIColor.systemOrange : UIColor.systemBlue.withAlphaComponent(0.85)
                    renderer.lineWidth = isSelected ? 6.0 : 3.5
                    renderer.setNeedsDisplay()
                } else if let renderer = mapView.renderer(for: overlay) as? MKCircleRenderer {
                    if let circle = overlay as? StayCircleOverlay {
                        let isSelected = circle.stayID == selectedItemID
                        renderer.fillColor = isSelected ? UIColor.systemOrange.withAlphaComponent(0.40) : UIColor.systemBlue.withAlphaComponent(0.25)
                        renderer.strokeColor = isSelected ? UIColor.systemOrange : UIColor.systemBlue.withAlphaComponent(0.85)
                        renderer.lineWidth = isSelected ? 3.0 : 1.5
                        renderer.setNeedsDisplay()
                    } else if let circle = overlay as? SingleObservationOverlay {
                        let isSelected = circle.pointID == selectedItemID
                        renderer.fillColor = isSelected ? UIColor.systemOrange.withAlphaComponent(0.50) : UIColor.systemGray.withAlphaComponent(0.30)
                        renderer.strokeColor = isSelected ? UIColor.systemOrange : UIColor.systemGray
                        renderer.lineWidth = isSelected ? 2.5 : 1.0
                        renderer.setNeedsDisplay()
                    } else if let debugCircle = overlay as? DebugPointCircleOverlay {
                        let isSelected = debugCircle.pointID == selectedItemID
                        switch debugCircle.status {
                        case .usable:
                            renderer.fillColor = isSelected ? UIColor.systemOrange.withAlphaComponent(0.40) : UIColor.systemTeal.withAlphaComponent(0.15)
                            renderer.strokeColor = isSelected ? UIColor.systemOrange : UIColor.systemTeal.withAlphaComponent(0.70)
                        case .suspicious:
                            renderer.fillColor = isSelected ? UIColor.systemOrange.withAlphaComponent(0.40) : UIColor.systemYellow.withAlphaComponent(0.25)
                            renderer.strokeColor = isSelected ? UIColor.systemOrange : UIColor.systemYellow.withAlphaComponent(0.85)
                        case .outlier:
                            renderer.fillColor = isSelected ? UIColor.systemOrange.withAlphaComponent(0.40) : UIColor.systemRed.withAlphaComponent(0.25)
                            renderer.strokeColor = isSelected ? UIColor.systemOrange : UIColor.systemRed.withAlphaComponent(0.85)
                        }
                        renderer.lineWidth = isSelected ? 3.0 : 1.2
                        renderer.setNeedsDisplay()
                    }
                } else if let heatRenderer = mapView.renderer(for: overlay) as? DwellHeatRenderer {
                    if let heatOverlay = overlay as? DwellHeatOverlay {
                        heatRenderer.isSelected = (heatOverlay.stayID == selectedItemID)
                        heatRenderer.setNeedsDisplay()
                    }
                }
            }
        }

        public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? SegmentPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                let isSelected = polyline.segmentID == selectedItemID
                renderer.strokeColor = isSelected ? UIColor.systemOrange : UIColor.systemBlue.withAlphaComponent(0.85)
                renderer.lineWidth = isSelected ? 6.0 : 3.5
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }

            if let heatCircle = overlay as? DwellHeatOverlay {
                let renderer = DwellHeatRenderer(overlay: heatCircle)
                renderer.isSelected = (heatCircle.stayID == selectedItemID)
                return renderer
            }

            if let stayCircle = overlay as? StayCircleOverlay {
                let renderer = MKCircleRenderer(circle: stayCircle)
                let isSelected = stayCircle.stayID == selectedItemID
                renderer.fillColor = isSelected ? UIColor.systemOrange.withAlphaComponent(0.40) : UIColor.systemBlue.withAlphaComponent(0.25)
                renderer.strokeColor = isSelected ? UIColor.systemOrange : UIColor.systemBlue.withAlphaComponent(0.85)
                renderer.lineWidth = isSelected ? 3.0 : 1.5
                return renderer
            }

            if let singleObs = overlay as? SingleObservationOverlay {
                let renderer = MKCircleRenderer(circle: singleObs)
                let isSelected = singleObs.pointID == selectedItemID
                renderer.fillColor = isSelected ? UIColor.systemOrange.withAlphaComponent(0.50) : UIColor.systemGray.withAlphaComponent(0.30)
                renderer.strokeColor = isSelected ? UIColor.systemOrange : UIColor.systemGray
                renderer.lineWidth = isSelected ? 2.5 : 1.0
                return renderer
            }

            if let debugCircle = overlay as? DebugPointCircleOverlay {
                let renderer = MKCircleRenderer(circle: debugCircle)
                let isSelected = debugCircle.pointID == selectedItemID
                switch debugCircle.status {
                case .usable:
                    renderer.fillColor = isSelected ? UIColor.systemOrange.withAlphaComponent(0.40) : UIColor.systemTeal.withAlphaComponent(0.15)
                    renderer.strokeColor = isSelected ? UIColor.systemOrange : UIColor.systemTeal.withAlphaComponent(0.70)
                case .suspicious:
                    renderer.fillColor = isSelected ? UIColor.systemOrange.withAlphaComponent(0.40) : UIColor.systemYellow.withAlphaComponent(0.25)
                    renderer.strokeColor = isSelected ? UIColor.systemOrange : UIColor.systemYellow.withAlphaComponent(0.85)
                case .outlier:
                    renderer.fillColor = isSelected ? UIColor.systemOrange.withAlphaComponent(0.40) : UIColor.systemRed.withAlphaComponent(0.25)
                    renderer.strokeColor = isSelected ? UIColor.systemOrange : UIColor.systemRed.withAlphaComponent(0.85)
                }
                renderer.lineWidth = isSelected ? 3.0 : 1.2
                return renderer
            }

            if let legacySingleton = overlay as? SingletonCircleOverlay {
                let renderer = MKCircleRenderer(circle: legacySingleton)
                let isSelected = legacySingleton.singletonID == selectedItemID
                renderer.fillColor = isSelected ? UIColor.systemOrange.withAlphaComponent(0.35) : UIColor.systemBlue.withAlphaComponent(0.20)
                renderer.strokeColor = isSelected ? UIColor.systemOrange : UIColor.systemBlue.withAlphaComponent(0.80)
                renderer.lineWidth = isSelected ? 3.0 : 1.5
                return renderer
            }

            return MKOverlayRenderer(overlay: overlay)
        }

        @objc public func handleMapTap(_ recognizer: UITapGestureRecognizer) {
            guard let mapView = recognizer.view as? MKMapView else { return }
            let tapPoint = recognizer.location(in: mapView)

            let hitTolerance: Double = 32.0
            var bestID: String? = nil
            var bestDistance: Double = .infinity

            // 1. Hit test stays
            for stay in stays {
                let screen = mapView.convert(
                    CLLocationCoordinate2D(latitude: stay.latitude, longitude: stay.longitude),
                    toPointTo: mapView
                )
                let dx = Double(tapPoint.x - screen.x)
                let dy = Double(tapPoint.y - screen.y)
                let dist = (dx * dx + dy * dy).squareRoot()
                if dist < bestDistance {
                    bestDistance = dist
                    if dist <= hitTolerance {
                        bestID = stay.id
                    }
                }
            }

            // 2. Hit test single observations
            for obs in singleObservations {
                let screen = mapView.convert(
                    CLLocationCoordinate2D(latitude: obs.latitude, longitude: obs.longitude),
                    toPointTo: mapView
                )
                let dx = Double(tapPoint.x - screen.x)
                let dy = Double(tapPoint.y - screen.y)
                let dist = (dx * dx + dy * dy).squareRoot()
                if dist < bestDistance {
                    bestDistance = dist
                    if dist <= hitTolerance {
                        let tsMs = Int64(obs.timestamp.timeIntervalSince1970 * 1000)
                        bestID = "obs_\(tsMs)"
                    }
                }
            }

            // 3. Hit test segments
            for segment in segments {
                guard segment.points.count >= 2 else { continue }
                let screenPoints: [(x: Double, y: Double)] = segment.points.map { pt in
                    let screen = mapView.convert(
                        CLLocationCoordinate2D(latitude: pt.latitude, longitude: pt.longitude),
                        toPointTo: mapView
                    )
                    return (x: Double(screen.x), y: Double(screen.y))
                }
                let dist = TrajectoryMath.distanceFromPointToPolyline(
                    point: (x: Double(tapPoint.x), y: Double(tapPoint.y)),
                    polyline: screenPoints
                )
                if dist < bestDistance {
                    bestDistance = dist
                    if dist <= hitTolerance {
                        bestID = segment.id
                    }
                }
            }

            // 4. Hit test debug points
            for debugCircle in debugOverlays {
                let screen = mapView.convert(debugCircle.coordinate, toPointTo: mapView)
                let dx = Double(tapPoint.x - screen.x)
                let dy = Double(tapPoint.y - screen.y)
                let dist = (dx * dx + dy * dy).squareRoot()
                if dist < bestDistance {
                    bestDistance = dist
                    if dist <= hitTolerance {
                        bestID = debugCircle.pointID
                    }
                }
            }

            let newSelectedID: String?
            if let targetID = bestID {
                newSelectedID = (selectedItemID == targetID) ? nil : targetID
            } else {
                newSelectedID = nil
            }

            if newSelectedID != selectedItemID {
                selectedItemID = newSelectedID
                onSelectItem?(newSelectedID)
                refreshSelectionRendering(mapView: mapView)
            }
        }
    }
}
