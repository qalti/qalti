import Foundation
import SwiftUI

/// Marker to visualize on top of the latest replay screenshot (image pixel space).
struct ReplayMarker: Identifiable {
    enum Kind { case tap, move, zoom }

    let id = UUID()
    let x: Int
    let y: Int
    let kind: Kind
    let direction: String?
    let amount: Double?
    var scale: Double? = nil
}

/// Observable state object that stores screenshot + markers for replay overlays.
final class ReplayState: ObservableObject {
    @Published var screenshot: PlatformImage? = nil
    @Published var markers: [ReplayMarker] = []

    func reset() {
        screenshot = nil
        markers = []
    }
}
