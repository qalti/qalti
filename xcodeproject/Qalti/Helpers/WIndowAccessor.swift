//
//  WIndowAccessor.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 04.03.2025.
//

import SwiftUI
import Logging

#if os(macOS)
import AppKit

struct SimulatorWindowAspectRatioManager: NSViewRepresentable {
    /// The image size used to compute the aspect ratio.
    var imageSize: CGSize?
    
    // Track if we initiated the resize to avoid reacting to our own changes
    class Coordinator: NSObject {
        var imageSize: CGSize?
        var isPerformingOwnResize = false
        var windowObserver: NSObjectProtocol?
        var debounceWorkItem: DispatchWorkItem?
        
        init(imageSize: CGSize?) {
            self.imageSize = imageSize
            super.init()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(imageSize: imageSize)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            setupWindowObserver(for: view, coordinator: context.coordinator)
            updateWindow(from: view, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Update coordinator's imageSize if it changed
        if context.coordinator.imageSize != imageSize {
            context.coordinator.imageSize = imageSize
        }
        
        DispatchQueue.main.async {
            setupWindowObserver(for: nsView, coordinator: context.coordinator)
            updateWindow(from: nsView, coordinator: context.coordinator)
        }
    }
    
    func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        // Cancel any pending work
        coordinator.debounceWorkItem?.cancel()
        
        // Remove window observer if it exists
        if let observer = coordinator.windowObserver {
            NotificationCenter.default.removeObserver(observer)
            coordinator.windowObserver = nil
        }
    }
    
    private func setupWindowObserver(for nsView: NSView, coordinator: Coordinator) {
        guard let window = nsView.window, coordinator.windowObserver == nil else { return }
        
        coordinator.windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didEndLiveResizeNotification,
            object: window,
            queue: .main
        ) { [weak window] _ in
            // Only respond to external resize operations
            guard let window, coordinator.isPerformingOwnResize == false, window.inLiveResize == false else { return }
            // Cancel any pending debounce work
            coordinator.debounceWorkItem?.cancel()
            
            // Create a new work item with a delay
            let workItem = DispatchWorkItem {
                guard let view = window.contentView else { return }
                updateWindow(from: view, coordinator: coordinator)
            }
            
            // Store the work item for potential cancellation
            coordinator.debounceWorkItem = workItem
            
            // Execute after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
        }
    }

    private func updateWindow(from nsView: NSView, coordinator: Coordinator) {
        guard let window = nsView.window else { return }
        guard coordinator.isPerformingOwnResize == false else { return }
        guard window.inLiveResize == false else { return }

        if let imageSize = coordinator.imageSize, imageSize.height > 0 {
            // Compute the titlebar height by comparing the window's frame
            // with the window's content area.

            let titleBarHeight: CGFloat

            if let windowFrameHeight = window.contentView?.frame.height {
                titleBarHeight = windowFrameHeight - window.contentLayoutRect.height
            } else {
                let contentRect = window.contentRect(forFrameRect: window.frame)
                titleBarHeight = window.frame.height - contentRect.height
            }

            // Create an adjusted size that includes the titlebar.
            // Now the entire window will tend toward this aspect ratio.
            let height = max(imageSize.height * 0.25, window.frame.height)
            let aspectRatio = imageSize.width / imageSize.height
            let adjustedSize = NSSize(
                width: (height * aspectRatio).rounded(.toNearestOrAwayFromZero),
                height: (height + titleBarHeight).rounded(.toNearestOrAwayFromZero)
            )

            let currentHeight = max(imageSize.height * 0.25 + titleBarHeight, window.frame.height)
            let currentContentHeight = currentHeight - titleBarHeight
            let newWidth = currentContentHeight * aspectRatio
            
            // Set flag before our own resize operation
            coordinator.isPerformingOwnResize = true
            
            window.setFrame(
                NSRect(
                    x: window.frame.origin.x,
                    y: window.frame.origin.y,
                    width: newWidth,
                    height: currentHeight
                ),
                display: true,
                animate: true
            )

            // Set the content aspect ratio.
            window.aspectRatio = adjustedSize

            // Clear flag after our resize operation is initiated
            // The animation completion will be handled on the main thread
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                coordinator.isPerformingOwnResize = false
            }
        } else {
            // No image or invalid size: allow free resizing.
            coordinator.isPerformingOwnResize = true
            window.resizeIncrements = NSMakeSize(1.0, 1.0)
            DispatchQueue.main.async {
                coordinator.isPerformingOwnResize = false
            }
        }
    }
}

struct CloseAppOnWindowCloseManager: NSViewRepresentable, Loggable {

    @EnvironmentObject private var errorCapturer: ErrorCapturerService

    @State private var windowObserver: NSObjectProtocol?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.update(with: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        update(with: nsView.window)
    }

    func update(with window: NSWindow?) {
        if windowObserver == nil, let window = window {
            windowObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window, // Only observe this specific window
                queue: .main
            ) { _ in
                // Kill idb_companion process before terminating the app
                let task = Process()
                task.launchPath = "/usr/bin/killall"
                task.arguments = ["idb_companion"]
                
                do {
                    try task.run()
                } catch {
                    errorCapturer.capture(error: error)
                    logger.error("Failed to kill idb_companion: \(error)")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }
}

struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.window = view.window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

#else

struct CloseAppOnWindowCloseManager: View {

    var body: some View {
        EmptyView()
    }

}

struct SimulatorWindowAspectRatioManager: View {
    var imageSize: CGSize?

    var body: some View {
        EmptyView()
    }
}

#endif
