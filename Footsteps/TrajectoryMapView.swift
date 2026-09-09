import SwiftUI
import MapKit

/// Status classification of an individual location fix for diagnostic map rendering.
public enum DebugPointStatus: String, Sendable {
    case usable = "Usable (≤100m)"
    case suspicious = "Suspicious (100–200m)"
    case outlier = "Outlier (>200m / Invalid)"
}

/// MKPolyline subclass that carries a deterministic segment identifier.
public final class SegmentPolyline: MKPolyline {
    public var segmentID: String = ""

    public static func create(from segment: TrajectorySegment) -> SegmentPolyline {
        let coords = segment.points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        let polyline = SegmentPolyline(coordinates: coords, count: coords.count)
        polyline.segmentID = segment.id
        return polyline
    }
}

/// MKCircle subclass representing an isolated location point or stationary dwell with uncertainty radius.
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

/// MKCircle subclass representing a raw observation fix for live diagnostic debugging.
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

/// SwiftUI wrapper for MKMapView rendering segmented trajectory lines, singletons, and diagnostic debug overlays.
public struct TrajectoryMapView: UIViewRepresentable {
    public let segments: [TrajectorySegment]
    public let singletons: [TrajectorySingleton]
    public let rawPoints: [TrajectoryPoint]
    public let showDebugOverlay: Bool
    public let dayKey: String
    @Binding public var selectedSegmentID: String?

    public init(
        segments: [TrajectorySegment],
        singletons: [TrajectorySingleton] = [],
        rawPoints: [TrajectoryPoint] = [],
        showDebugOverlay: Bool = false,
        dayKey: String = "",
        selectedSegmentID: Binding<String?> = .constant(nil)
    ) {
        self.segments = segments
        self.singletons = singletons
        self.rawPoints = rawPoints
        self.showDebugOverlay = showDebugOverlay
        self.dayKey = dayKey
        self._selectedSegmentID = selectedSegmentID
    }

    public func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = false

        // Native compass button positioned at bottom leading
        let compassButton = MKCompassButton(mapView: mapView)
        compassButton.compassVisibility = .adaptive
        compassButton.translatesAutoresizingMaskIntoConstraints = false
        mapView.addSubview(compassButton)

        // Native user tracking button positioned at bottom trailing
        let trackingButton = MKUserTrackingButton(mapView: mapView)
        trackingButton.translatesAutoresizingMaskIntoConstraints = false
        mapView.addSubview(trackingButton)

        NSLayoutConstraint.activate([
            compassButton.leadingAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            compassButton.bottomAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            trackingButton.trailingAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            trackingButton.bottomAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])

        // Tap gesture for forgiving trajectory, singleton, and debug point hit testing
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMapTap(_:))
        )
        mapView.addGestureRecognizer(tapGesture)

        return mapView
    }

    public func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onSelectSegment = { newSelectedID in
            DispatchQueue.main.async {
                self.selectedSegmentID = newSelectedID
            }
        }

        _ = coordinator.updateMapOverlays(
            mapView: mapView,
            segments: segments,
            singletons: singletons,
            rawPoints: rawPoints,
            showDebugOverlay: showDebugOverlay,
            dayKey: dayKey
        )

        // Update selection styling if selectedSegmentID changed externally
        if selectedSegmentID != coordinator.selectedSegmentID {
            coordinator.selectedSegmentID = selectedSegmentID
            coordinator.refreshSelectionRendering(mapView: mapView)
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public final class Coordinator: NSObject, MKMapViewDelegate {
        public var segments: [TrajectorySegment] = []
        public var singletons: [TrajectorySingleton] = []
        public var debugOverlays: [DebugPointCircleOverlay] = []
        public var selectedSegmentID: String? = nil
        public var lastRenderedDayKey: String? = nil
        public var lastRenderedSignature: String = ""
        public var onSelectSegment: ((String?) -> Void)?

        public func updateMapOverlays(
            mapView: MKMapView,
            segments: [TrajectorySegment],
            singletons: [TrajectorySingleton] = [],
            rawPoints: [TrajectoryPoint] = [],
            showDebugOverlay: Bool = false,
            dayKey: String
        ) -> Bool {
            let dayChanged = (lastRenderedDayKey != dayKey)
            let signature = "\(dayKey)_\(showDebugOverlay)_\(segments.count)_\(singletons.count)_\(rawPoints.count)_\(segments.map(\.id).joined(separator: ","))"

            guard signature != lastRenderedSignature || dayChanged else {
                return false
            }

            lastRenderedSignature = signature
            self.segments = segments
            self.singletons = singletons
            self.debugOverlays = []

            mapView.removeOverlays(mapView.overlays)

            for segment in segments {
                let polyline = SegmentPolyline.create(from: segment)
                mapView.addOverlay(polyline)
            }

            for singleton in singletons {
                let circle = SingletonCircleOverlay.create(from: singleton)
                mapView.addOverlay(circle)
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
            if dayChanged {
                lastRenderedDayKey = dayKey
                if let firstRect = mapView.overlays.first?.boundingMapRect {
                    let unionRect = mapView.overlays.reduce(firstRect) { $0.union($1.boundingMapRect) }
                    if !unionRect.isNull && unionRect.size.width > 0 && unionRect.size.height > 0 {
                        let padding = UIEdgeInsets(top: 60, left: 40, bottom: 60, right: 40)
                        mapView.setVisibleMapRect(unionRect, edgePadding: padding, animated: true)
                        didFrame = true
                    }
                } else {
                    didFrame = true
                }
            }

            return didFrame
        }

        public func refreshSelectionRendering(mapView: MKMapView) {
            for overlay in mapView.overlays {
                if let renderer = mapView.renderer(for: overlay) as? MKPolylineRenderer {
                    let isSelected = (overlay as? SegmentPolyline)?.segmentID == selectedSegmentID
                    renderer.strokeColor = isSelected ? UIColor.systemOrange : UIColor.systemBlue.withAlphaComponent(0.85)
                    renderer.lineWidth = isSelected ? 6.0 : 3.5
                    renderer.setNeedsDisplay()
                } else if let renderer = mapView.renderer(for: overlay) as? MKCircleRenderer {
                    if let circle = overlay as? SingletonCircleOverlay {
                        let isSelected = circle.singletonID == selectedSegmentID
                        renderer.fillColor = isSelected ? UIColor.systemOrange.withAlphaComponent(0.35) : UIColor.systemBlue.withAlphaComponent(0.20)
                        renderer.strokeColor = isSelected ? UIColor.systemOrange : UIColor.systemBlue.withAlphaComponent(0.80)
                        renderer.lineWidth = isSelected ? 3.0 : 1.5
                        renderer.setNeedsDisplay()
                    } else if let debugCircle = overlay as? DebugPointCircleOverlay {
                        let isSelected = debugCircle.pointID == selectedSegmentID
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
                }
            }
        }

        public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? SegmentPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                let isSelected = polyline.segmentID == selectedSegmentID
                renderer.strokeColor = isSelected ? UIColor.systemOrange : UIColor.systemBlue.withAlphaComponent(0.85)
                renderer.lineWidth = isSelected ? 6.0 : 3.5
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }

            if let circle = overlay as? SingletonCircleOverlay {
                let renderer = MKCircleRenderer(circle: circle)
                let isSelected = circle.singletonID == selectedSegmentID
                renderer.fillColor = isSelected ? UIColor.systemOrange.withAlphaComponent(0.35) : UIColor.systemBlue.withAlphaComponent(0.20)
                renderer.strokeColor = isSelected ? UIColor.systemOrange : UIColor.systemBlue.withAlphaComponent(0.80)
                renderer.lineWidth = isSelected ? 3.0 : 1.5
                return renderer
            }

            if let debugCircle = overlay as? DebugPointCircleOverlay {
                let renderer = MKCircleRenderer(circle: debugCircle)
                let isSelected = debugCircle.pointID == selectedSegmentID
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

            return MKOverlayRenderer(overlay: overlay)
        }

        @objc public func handleMapTap(_ recognizer: UITapGestureRecognizer) {
            guard let mapView = recognizer.view as? MKMapView else { return }
            let tapPoint = recognizer.location(in: mapView)

            // Forgiving touch target tolerance in points (~30pt radius)
            let hitTolerance: Double = 30.0

            var bestID: String? = nil
            var bestDistance: Double = .infinity

            // 1. Hit test segments
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

            // 2. Hit test singletons
            for singleton in singletons {
                let screen = mapView.convert(
                    CLLocationCoordinate2D(latitude: singleton.point.latitude, longitude: singleton.point.longitude),
                    toPointTo: mapView
                )
                let dx = Double(tapPoint.x - screen.x)
                let dy = Double(tapPoint.y - screen.y)
                let dist = (dx * dx + dy * dy).squareRoot()
                if dist < bestDistance {
                    bestDistance = dist
                    if dist <= hitTolerance {
                        bestID = singleton.id
                    }
                }
            }

            // 3. Hit test debug points
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
                newSelectedID = (selectedSegmentID == targetID) ? nil : targetID
            } else {
                newSelectedID = nil
            }

            if newSelectedID != selectedSegmentID {
                selectedSegmentID = newSelectedID
                onSelectSegment?(newSelectedID)
                refreshSelectionRendering(mapView: mapView)
            }
        }
    }
}
