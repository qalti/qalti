//
//  TouchMarkerView.swift
//  Qalti
//
//  Created by k Slavnov on 29/08/2025.
//

import SwiftUI
import Foundation

// MARK: - Replay Overlay View (extracted for compile-time simplicity)
struct ReplayOverlayView: View {
    let screenshot: PlatformImage
    let markers: [ReplayMarker]
    
    var body: some View {
        ZStack {
            Color.secondarySystemBackground
            Image(platformImage: screenshot)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .overlay(alignment: .center) {
                    GeometryReader { geo in
                        let imageSize = Self.fittedImageSize(screenshot, geo.size)
                        let originX = (geo.size.width - imageSize.width) / 2
                        let originY = (geo.size.height - imageSize.height) / 2
                        let scaleX = imageSize.width / screenshot.size.width
                        let scaleY = imageSize.height / screenshot.size.height
                        ZStack {
                            ForEach(markers) { marker in
                                let markerX = originX + CGFloat(marker.x) * scaleX
                                let markerY = originY + CGFloat(marker.y) * scaleY
                                let markerColor = Color(red: 1.0, green: 0.55, blue: 0.0)
                                
                                // --- Draw Base Ripple Marker for ALL gestures ---
                                TouchMarkerView(kind: marker.kind, direction: marker.direction, amount: marker.amount, scale: marker.scale)
                                    .frame(width: max(imageSize.width, imageSize.height) * 0.05, height: max(imageSize.width, imageSize.height) * 0.05)
                                    .position(x: markerX, y: markerY)
                                
                                // --- Draw Gesture-Specific Overlays (Arrows for Swipe and Zoom) ---
                                if marker.kind == .move, let amt = marker.amount, amt > 0 {
                                    let dir = marker.direction?.lowercased() ?? ""
                                    let pixelLen: CGFloat = amt > 1.0 ? CGFloat(amt) : CGFloat(amt) * screenshot.size.height
                                    let isHorizontal = (dir == "left" || dir == "right")
                                    let sign: CGFloat = (dir == "left" || dir == "up") ? -1.0 : 1.0
                                    let lenDisp = pixelLen * (isHorizontal ? scaleX : scaleY)
                                    let dx = isHorizontal ? sign * lenDisp : 0
                                    let dy = isHorizontal ? 0 : sign * lenDisp
                                    let markerViewSize = max(imageSize.width, imageSize.height) * 0.05
                                    SwipePathAbsolute(
                                        from: CGPoint(x: markerX, y: markerY),
                                        to: CGPoint(x: markerX + dx, y: markerY + dy),
                                        containerSize: geo.size,
                                        color: markerColor,
                                        startOffset: markerViewSize + 2 // start after 3rd ring
                                    )
                                }
                            }
                        }
                    }
                }
        }
    }
    
    private static func fittedImageSize(_ image: PlatformImage, _ container: CGSize) -> CGSize {
        let imageSize = image.size
        guard imageSize.width > 0 && imageSize.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
}


// Dotted path between two absolute points in overlay space
private struct SwipePathAbsolute: View {
    let from: CGPoint
    let to: CGPoint
    let containerSize: CGSize
    let color: Color
    let startOffset: CGFloat // distance to skip from start along the path
    
    var body: some View {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = max(1.0, hypot(dx, dy))
        let ux = dx / length
        let uy = dy / length

        // Start after the 3-rings visualization
        let effectiveStart = CGPoint(x: from.x + ux * startOffset, y: from.y + uy * startOffset)
        let effectiveLength = max(0, length - startOffset)

        let isHorizontal = abs(dx) >= abs(dy)

        // Slightly fewer rectangles than before
        let steps = max(4, Int(effectiveLength / 18))

        // Base dimensions for rectangles
        let baseLong: CGFloat = 12
        let startLong: CGFloat = baseLong * 0.5 // start 2x smaller on the changing side
        let minLong: CGFloat = 4
        let constantShort: CGFloat = 18 // 3x bigger constant size

        // Opacity fades with distance from the start
        let startAlpha: Double = 0.85
        let endAlpha: Double = 0.25

        ZStack {
            // Skip the closest rectangle to the point (start from index 1)
            ForEach(1..<steps, id: \.self) { i in
                let t = CGFloat(i) / CGFloat(max(1, steps - 1))
                let x = effectiveStart.x + ux * effectiveLength * t
                let y = effectiveStart.y + uy * effectiveLength * t

                // Long side shrinks along movement axis; short side stays constant
                let longSize = startLong - (startLong - minLong) * t
                let width: CGFloat = isHorizontal ? longSize : constantShort
                let height: CGFloat = isHorizontal ? constantShort : longSize

                // Remove all elements that would appear inside the 3-circle visualization
                let radialDistance = hypot(x - from.x, y - from.y)
                let exclusionRadius = startOffset + max(constantShort, longSize) / 2
                if radialDistance <= exclusionRadius { /* skip drawing inside center */ }
                else {
                    let alpha = startAlpha - (startAlpha - endAlpha) * Double(t)
                    Rectangle()
                        .fill(color.opacity(alpha))
                        .frame(width: width, height: height)
                        .position(x: x, y: y)
                }
            }
        }
    }
}
