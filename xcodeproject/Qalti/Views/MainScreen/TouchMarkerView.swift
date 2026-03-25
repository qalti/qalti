//
//  TouchMarkerView.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 05.11.25.
//

import SwiftUI

// MARK: - Specialized Marker Components

// --- Arrow Drawing Primitive ---
private struct ArrowView: View {
    let startPoint: CGPoint
    let endPoint: CGPoint
    let color: Color
    let thickness: CGFloat

    var body: some View {
        Canvas { context, size in
            let angle = atan2(endPoint.y - startPoint.y, endPoint.x - startPoint.x)
            let headLength = thickness * 3
            let lineEndPoint = CGPoint(
                x: endPoint.x - headLength * 0.8 * cos(angle),
                y: endPoint.y - headLength * 0.8 * sin(angle)
            )
            var linePath = Path()
            linePath.move(to: startPoint)
            linePath.addLine(to: lineEndPoint)
            context.stroke(linePath, with: .color(color), lineWidth: thickness)
            
            let p1 = endPoint
            let p2 = CGPoint(x: endPoint.x - headLength * cos(angle - .pi / 6), y: endPoint.y - headLength * sin(angle - .pi / 6))
            let p3 = CGPoint(x: endPoint.x - headLength * cos(angle + .pi / 6), y: endPoint.y - headLength * sin(angle + .pi / 6))
            
            var trianglePath = Path()
            trianglePath.move(to: p1)
            trianglePath.addLine(to: p2)
            trianglePath.addLine(to: p3)
            trianglePath.closeSubpath()
            context.fill(trianglePath, with: .color(color))
        }
    }
}

// --- Specialized View for ZOOM ---
private struct ZoomMarkerView: View {
    let scale: Double
    let color: Color
    
    var body: some View {
        ZStack {
            let zoomIn = scale > 1.0
            // 1. Custom Circles for Zoom
            if zoomIn {
                Circle()
                    .stroke(color.opacity(0.4), lineWidth: 3.6)
                    .scaleEffect(0.6)
                Circle()
                    .stroke(color.opacity(0.5), lineWidth: 2.1)
                    .scaleEffect(1.2)
            } else {
                Circle()
                    .stroke(color.opacity(0.5), lineWidth: 4)
                    .scaleEffect(0.3)
                Circle()
                    .stroke(color.opacity(0.7), lineWidth: 1.0)
                    .scaleEffect(1.2)
            }

            // 2. The Arrows, drawn on top of the new circles
            GeometryReader { geo in
                let size = geo.size
                let thickness = size.width * 0.07
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxRadius = size.width / 2
                let innerRadius = maxRadius * 0.2
                let extendedRadius = maxRadius * (zoomIn ? 1.0 : 0.9)
                let innerPoint1 = CGPoint(x: center.x - innerRadius, y: center.y - innerRadius)
                let innerPoint2 = CGPoint(x: center.x + innerRadius, y: center.y + innerRadius)
                let extendedPoint1 = CGPoint(x: center.x - extendedRadius, y: center.y - extendedRadius)
                let extendedPoint2 = CGPoint(x: center.x + extendedRadius, y: center.y + extendedRadius)
                
                ZStack {
                    if zoomIn { // Zoom In
                        ArrowView(startPoint: innerPoint1, endPoint: extendedPoint1, color: color, thickness: thickness)
                        ArrowView(startPoint: innerPoint2, endPoint: extendedPoint2, color: color, thickness: thickness)
                    } else { // Zoom Out
                        ArrowView(startPoint: extendedPoint1, endPoint: innerPoint1, color: color, thickness: thickness)
                        ArrowView(startPoint: extendedPoint2, endPoint: innerPoint2, color: color, thickness: thickness)
                    }
                }
            }
        }
    }
}

// --- Specialized View for TAP and MOVE ---
private struct DefaultMarkerView: View {
    let color: Color
    
    var body: some View {
        ZStack {
            // The original "ripple" effect
            Circle()
                .stroke(color.opacity(0.9), lineWidth: 2.1)
                .background(Circle().fill(color.opacity(0.12)))
            Circle()
                .stroke(color.opacity(0.7), lineWidth: 2.1)
                .scaleEffect(1.5)
            Circle()
                .stroke(color.opacity(0.5), lineWidth: 2.1)
                .scaleEffect(2.0)
            
            // The center dot
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
        }
    }
}


// MARK: - The Main "Switcher" View
struct TouchMarkerView: View {
    let kind: ReplayMarker.Kind
    var direction: String? = nil
    var amount: Double? = nil
    var scale: Double? = nil
    
    private var qaltiOrange: Color { Color(red: 1.0, green: 0.55, blue: 0.0) }
    
    @ViewBuilder
    var body: some View {
        switch kind {
        case .zoom:
            if let scale = scale {
                ZoomMarkerView(scale: scale, color: qaltiOrange)
            } else {
                // Fallback to default if scale is missing for some reason
                DefaultMarkerView(color: qaltiOrange)
            }
        case .tap, .move:
            DefaultMarkerView(color: qaltiOrange)
        }
    }
}
