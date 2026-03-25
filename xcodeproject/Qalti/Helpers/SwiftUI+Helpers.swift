//
//  SwiftUI+Helpers.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 10.03.2025.
//

import SwiftUI
import AppKit

// MARK: - Color Extensions

extension Color {
    func mix(_ secondColor: Color, _ value: Float) -> Color {
        let aComponents = self.rgba()
        let bComponents = secondColor.rgba()

        return Color(
            red: aComponents[0] + (bComponents[0] - aComponents[0]) * CGFloat(value),
            green: aComponents[1] + (bComponents[1] - aComponents[1]) * CGFloat(value),
            blue: aComponents[2] + (bComponents[2] - aComponents[2]) * CGFloat(value),
            opacity: aComponents[3] + (bComponents[3] - aComponents[3]) * CGFloat(value)
        )
    }

    private func rgba() -> [CGFloat] {
        var components: [CGFloat] = []
        if #available(iOS 17.0, macOS 14.0, *) {
            guard let resolved = self.resolve(in: EnvironmentValues()).cgColor.components else { return [0, 0, 0, 0] }
            components = resolved
        } else {
            guard let fromCGColor = self.cgColor?.components else { return [0, 0, 0, 0] }
            components = fromCGColor
        }

        if components.count == 1 {
            components = [components[0], components[0], components[0], 1.0]
        } else if components.count == 2 {
            components = [components[0], components[0], components[0], components[1]]
        } else if components.count == 3 {
            components = [components[0], components[1], components[2], 1]
        } else if components.count == 4 {
            components = [components[0], components[1], components[2], components[3]]
        } else {
            components = [0, 0, 0, 0]
        }
        return components
    }
}

// MARK: - View Extensions

extension View {
    /// Conditionally applies a transformation to the view
    /// - Parameters:
    ///   - condition: Boolean condition to check
    ///   - transform: Closure that transforms the view when condition is true
    /// - Returns: The transformed view if condition is true, otherwise the original view
    @ViewBuilder
    func `if`(_ condition: Bool, transform: (Self) -> some View) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Escape key handling
private struct EscapeKeyMonitor: NSViewRepresentable {
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onEscape: onEscape) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.start()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Coordinator {
        private let onEscape: () -> Void
        private var monitor: Any?

        init(onEscape: @escaping () -> Void) {
            self.onEscape = onEscape
        }

        func start() {
            stop()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                // 53 is the keyCode for Escape on macOS
                if event.keyCode == 53 {
                    self?.onEscape()
                    return nil // consume the event
                }
                return event
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit { stop() }
    }
}

extension View {
    /// Calls the provided closure when the Escape key is pressed
    /// - Parameter perform: Action to run when Escape is pressed
    /// - Returns: Modified view that listens for Escape key presses
    func onEscapePressed(perform: @escaping () -> Void) -> some View {
        return background(EscapeKeyMonitor(onEscape: perform))
    }
}
