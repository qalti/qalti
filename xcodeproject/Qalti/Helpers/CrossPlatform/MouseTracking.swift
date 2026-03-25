//
//  MouseTracking.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 11.03.2025.
//

import SwiftUI


enum TrackingAreaMouseEvent {
    case active(CGPoint)
    case ended
}

#if os(macOS)
extension View {
    func onContinuousHover(perform action: @escaping (TrackingAreaMouseEvent) -> Void) -> some View {
        self.overlay(
            MouseTrackingView(onMouseEvent: action)
        )
    }
}

struct MouseTrackingView: NSViewRepresentable {
    let onMouseEvent: (TrackingAreaMouseEvent) -> Void

    func makeNSView(context: Context) -> MouseTrackingNSView {
        let view = MouseTrackingNSView()
        view.onMouseEvent = onMouseEvent
        return view
    }

    func updateNSView(_ nsView: MouseTrackingNSView, context: Context) {
        nsView.onMouseEvent = onMouseEvent
    }

    class MouseTrackingNSView: NSView {
        var onMouseEvent: ((TrackingAreaMouseEvent) -> Void)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()

            for trackingArea in trackingAreas {
                removeTrackingArea(trackingArea)
            }

            let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeAlways]
            let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(trackingArea)
        }

        override func mouseMoved(with event: NSEvent) {
            let nsPoint = convert(event.locationInWindow, from: nil)
            // Convert NSView coordinates (origin at bottom-left) to SwiftUI coordinates (origin at top-left)
            let swiftUIPoint = CGPoint(x: nsPoint.x, y: bounds.height - nsPoint.y)
            onMouseEvent?(.active(swiftUIPoint))
        }

        override func mouseExited(with event: NSEvent) {
            onMouseEvent?(.ended)
        }
    }
}
#else
extension View {
    func onContinuousHover(perform action: @escaping (TrackingAreaMouseEvent) -> Void) -> some View {
        return self
    }
}
#endif

