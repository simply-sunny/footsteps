import SwiftUI
import MapKit

/// MKPolyline subclass that carries a deterministic segment identifier.
final class SegmentPolyline: MKPolyline {
    var segmentID: String = ""

    static func create(from segment: TrajectorySegment) -> SegmentPolyline {
        let coords = segment.points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        let polyline = SegmentPolyline(coordinates: coords, count: coords.count)
        polyline.segmentID = segment.id
        return polyline
    }
}

/// SwiftUI wrapper for MKMapView rendering real segmented trajectory lines with selectable segments.
struct TrajectoryMapView: UIViewRepresentable {
    let segments: [TrajectorySegment]
    @Binding var selectedSegmentID: String?

    init(
        segments: [TrajectorySegment],
        selectedSegmentID: Binding<String?> = .constant(nil)
    ) {
        self.segments = segments
        self._selectedSegmentID = selectedSegmentID
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true

        // Native user tracking button
        let trackingButton = MKUserTrackingButton(mapView: mapView)
        trackingButton.translatesAutoresizingMaskIntoConstraints = false
        mapView.addSubview(trackingButton)

        NSLayoutConstraint.activate([
            trackingButton.trailingAnchor.constraint(equalTo: mapView.trailingAnchor, constant: -16),
            trackingButton.topAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.topAnchor, constant: 16)
        ])

        // Tap gesture for forgiving trajectory hit testing
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMapTap(_:))
        )
        mapView.addGestureRecognizer(tapGesture)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.segments = segments
        coordinator.onSelectSegment = { newSelectedID in
            DispatchQueue.main.async {
                self.selectedSegmentID = newSelectedID
            }
        }

        let segmentIDs = segments.map(\.id)
        let segmentsChanged = segmentIDs != coordinator.lastRenderedSegmentIDs

        if segmentsChanged {
            coordinator.lastRenderedSegmentIDs = segmentIDs

            // Remove previous overlays
            mapView.removeOverlays(mapView.overlays)

            guard !segments.isEmpty else {
                return
            }

            // Add polyline overlay for each segment
            for segment in segments {
                let polyline = SegmentPolyline.create(from: segment)
                mapView.addOverlay(polyline)
            }

            // Frame visible map rect to bounding area of the new day's segments (preserves free pan afterwards)
            if let firstRect = mapView.overlays.first?.boundingMapRect {
                let unionRect = mapView.overlays.reduce(firstRect) { $0.union($1.boundingMapRect) }
                if !unionRect.isNull && unionRect.size.width > 0 && unionRect.size.height > 0 {
                    let padding = UIEdgeInsets(top: 60, left: 40, bottom: 60, right: 40)
                    mapView.setVisibleMapRect(unionRect, edgePadding: padding, animated: true)
                }
            }
        }

        // Update selection styling if selectedSegmentID changed externally
        if selectedSegmentID != coordinator.selectedSegmentID {
            coordinator.selectedSegmentID = selectedSegmentID
            for overlay in mapView.overlays {
                if let renderer = mapView.renderer(for: overlay) as? MKPolylineRenderer {
                    let isSelected = (overlay as? SegmentPolyline)?.segmentID == selectedSegmentID
                    renderer.strokeColor = isSelected ? UIColor.systemOrange : UIColor.systemBlue.withAlphaComponent(0.85)
                    renderer.lineWidth = isSelected ? 6.0 : 3.5
                    renderer.setNeedsDisplay()
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var segments: [TrajectorySegment] = []
        var selectedSegmentID: String? = nil
        var lastRenderedSegmentIDs: [String] = []
        var onSelectSegment: ((String?) -> Void)?

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? SegmentPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                let isSelected = polyline.segmentID == selectedSegmentID
                renderer.strokeColor = isSelected ? UIColor.systemOrange : UIColor.systemBlue.withAlphaComponent(0.85)
                renderer.lineWidth = isSelected ? 6.0 : 3.5
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        @objc func handleMapTap(_ recognizer: UITapGestureRecognizer) {
            guard let mapView = recognizer.view as? MKMapView else { return }
            let tapPoint = recognizer.location(in: mapView)

            // Forgiving touch target tolerance in points (~30pt radius)
            let hitTolerance: Double = 30.0

            // Linear hit test over current day's segments (N points is small for 1 day, O(N) is < 1ms)
            var bestSegmentID: String? = nil
            var bestDistance: Double = .infinity

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
                        bestSegmentID = segment.id
                    }
                }
            }

            let newSelectedID: String?
            if let bestID = bestSegmentID {
                // Toggle selection if tapping the already selected segment
                newSelectedID = (selectedSegmentID == bestID) ? nil : bestID
            } else {
                // Tap far from any trajectory clears selection
                newSelectedID = nil
            }

            if newSelectedID != selectedSegmentID {
                selectedSegmentID = newSelectedID
                onSelectSegment?(newSelectedID)

                for overlay in mapView.overlays {
                    if let renderer = mapView.renderer(for: overlay) as? MKPolylineRenderer {
                        let isSelected = (overlay as? SegmentPolyline)?.segmentID == newSelectedID
                        renderer.strokeColor = isSelected ? UIColor.systemOrange : UIColor.systemBlue.withAlphaComponent(0.85)
                        renderer.lineWidth = isSelected ? 6.0 : 3.5
                        renderer.setNeedsDisplay()
                    }
                }
            }
        }
    }
}
