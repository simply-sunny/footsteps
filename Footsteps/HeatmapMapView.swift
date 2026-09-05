import SwiftUI
import MapKit

final class DensityPolygon: MKPolygon {
    var intensity: Double = 1.0
}

final class HeatmapOverlay: NSObject, MKOverlay {
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect
    let cells: [DensityCell]

    init(cells: [DensityCell]) {
        self.cells = cells
        if cells.isEmpty {
            self.coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
            self.boundingMapRect = .null
        } else {
            let minLat = cells.map(\.minLat).min() ?? 0
            let maxLat = cells.map(\.maxLat).max() ?? 0
            let minLon = cells.map(\.minLon).min() ?? 0
            let maxLon = cells.map(\.maxLon).max() ?? 0

            let nwPoint = MKMapPoint(CLLocationCoordinate2D(latitude: maxLat, longitude: minLon))
            let sePoint = MKMapPoint(CLLocationCoordinate2D(latitude: minLat, longitude: maxLon))

            self.coordinate = CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2.0,
                longitude: (minLon + maxLon) / 2.0
            )
            self.boundingMapRect = MKMapRect(
                x: min(nwPoint.x, sePoint.x),
                y: min(nwPoint.y, sePoint.y),
                width: max(abs(sePoint.x - nwPoint.x), 1.0),
                height: max(abs(sePoint.y - nwPoint.y), 1.0)
            )
        }
        super.init()
    }
}

final class HeatmapOverlayRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let heatmap = overlay as? HeatmapOverlay else { return }

        for cell in heatmap.cells {
            let nw = MKMapPoint(CLLocationCoordinate2D(latitude: cell.maxLat, longitude: cell.minLon))
            let se = MKMapPoint(CLLocationCoordinate2D(latitude: cell.minLat, longitude: cell.maxLon))

            let cellMapRect = MKMapRect(
                x: min(nw.x, se.x),
                y: min(nw.y, se.y),
                width: max(abs(se.x - nw.x), 1.0),
                height: max(abs(se.y - nw.y), 1.0)
            )

            guard mapRect.intersects(cellMapRect) else { continue }

            let cgRect = rect(for: cellMapRect)
            let alpha = min(max(cell.intensity * 0.7 + 0.15, 0.2), 0.85)

            context.setFillColor(UIColor.systemBlue.withAlphaComponent(alpha).cgColor)
            context.fill(cgRect)

            context.setStrokeColor(UIColor.systemBlue.withAlphaComponent(min(alpha + 0.2, 1.0)).cgColor)
            context.setLineWidth(1.0 / zoomScale)
            context.stroke(cgRect)
        }
    }
}

struct HeatmapMapView: UIViewRepresentable {
    let points: [LocationPoint]
    let selectedDate: Date

    init(points: [LocationPoint], selectedDate: Date = Date()) {
        self.points = points
        self.selectedDate = selectedDate
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator

        let dayChanged = coordinator.lastRenderedDate == nil ||
            !Calendar.current.isDate(coordinator.lastRenderedDate!, inSameDayAs: selectedDate)
        let countChanged = points.count != coordinator.lastRenderedPointsCount

        guard dayChanged || countChanged else {
            // Stable equality: avoid rebuilding overlays on unrelated redraws.
            return
        }

        coordinator.lastRenderedDate = selectedDate
        coordinator.lastRenderedPointsCount = points.count

        if dayChanged {
            coordinator.hasFramedCurrentDay = false
        }

        // Remove previous overlays
        mapView.removeOverlays(mapView.overlays)

        guard !points.isEmpty else {
            return
        }

        let coordinates = points.map { (latitude: $0.latitude, longitude: $0.longitude) }
        let cells = HeatmapGridMath.computeDensityGrid(coordinates: coordinates)
        guard !cells.isEmpty else { return }

        let overlay = HeatmapOverlay(cells: cells)
        mapView.addOverlay(overlay)

        // Only frame region if day changed or first points arrived, so user manual panning is preserved
        if !coordinator.hasFramedCurrentDay {
            let rect = overlay.boundingMapRect
            if !rect.isNull && rect.size.width > 0 && rect.size.height > 0 {
                let padding = UIEdgeInsets(top: 50, left: 50, bottom: 50, right: 50)
                mapView.setVisibleMapRect(rect, edgePadding: padding, animated: true)
                coordinator.hasFramedCurrentDay = true
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var lastRenderedDate: Date? = nil
        var lastRenderedPointsCount: Int = -1
        var hasFramedCurrentDay: Bool = false

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let heatmap = overlay as? HeatmapOverlay {
                return HeatmapOverlayRenderer(overlay: heatmap)
            }
            if let densityPoly = overlay as? DensityPolygon {
                let renderer = MKPolygonRenderer(polygon: densityPoly)
                let alpha = min(max(densityPoly.intensity * 0.7 + 0.15, 0.2), 0.85)
                renderer.fillColor = UIColor.systemBlue.withAlphaComponent(alpha)
                renderer.strokeColor = UIColor.systemBlue.withAlphaComponent(min(alpha + 0.2, 1.0))
                renderer.lineWidth = 1.0
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
