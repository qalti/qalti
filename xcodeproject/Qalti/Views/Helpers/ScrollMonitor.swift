//
//  ScrollMonitor.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 19.11.25.
//

import SwiftUI
import AppKit

class ScrollMonitor: ObservableObject {
    var onScroll: ((NSEvent) -> Void)?
    private var monitor: Any?

    init() {
        // We listen for scrollWheel events globally within the window
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.onScroll?(event)
            // Return the event so the ScrollView still processes it
            return event
        }
    }

    deinit {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
