//
//  PlatformWindowTitlebar.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 12.06.2025.
//

import SwiftUI

// MARK: - View Extension

extension Scene {
    func platformHideTitleBar() -> some Scene {
        #if os(macOS)
            return self.windowStyle(.hiddenTitleBar)
        #else
            return self
        #endif
    }
}
