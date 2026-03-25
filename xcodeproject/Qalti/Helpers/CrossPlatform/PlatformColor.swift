//
//  PlatformColor.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 02.06.2025.
//

import SwiftUI

#if os(macOS)
import AppKit

typealias PlatformColor = NSColor

extension NSColor {
    static let label = labelColor
}


/// Platform-specific system colors using NSColor for macOS
extension Color {
    // MARK: - Background Colors
    static let systemBackground = Color(NSColor.windowBackgroundColor)
    static let secondarySystemBackground = Color(NSColor.controlBackgroundColor)
    static let tertiarySystemBackground = Color(NSColor.controlColor)
    static let systemGroupedBackground = Color(NSColor.windowBackgroundColor)
    static let secondarySystemGroupedBackground = Color(NSColor.controlBackgroundColor)
    static let tertiarySystemGroupedBackground = Color(NSColor.controlColor)
    
    // MARK: - Fill Colors
    static let systemFill = Color(NSColor.quaternaryLabelColor)
    static let secondarySystemFill = Color(NSColor.tertiaryLabelColor)
    static let tertiarySystemFill = Color(NSColor.secondaryLabelColor)
    static let quaternarySystemFill = Color(NSColor.labelColor)

    // MARK: - Text Colors
    static let label = Color(NSColor.labelColor)
    static let secondaryLabel = Color(NSColor.secondaryLabelColor)
    static let tertiaryLabel = Color(NSColor.tertiaryLabelColor)
    static let quaternaryLabel = Color(NSColor.quaternaryLabelColor)
    static let placeholderText = Color(NSColor.placeholderTextColor)
    static let link = Color(NSColor.linkColor)
    
    // MARK: - Separator Colors
    static let separator = Color(NSColor.separatorColor)
    
    // MARK: - Gray Colors
    static let systemGray = Color(NSColor.systemGray)
}

#else
import UIKit

typealias PlatformColor = UIColor

/// Platform-specific system colors using UIColor for iOS and other platforms
extension Color {
    // MARK: - Background Colors
    static let systemBackground = Color(UIColor.systemBackground)
    static let secondarySystemBackground = Color(UIColor.secondarySystemBackground)
    static let tertiarySystemBackground = Color(UIColor.tertiarySystemBackground)
    static let systemGroupedBackground = Color(UIColor.systemGroupedBackground)
    static let secondarySystemGroupedBackground = Color(UIColor.secondarySystemGroupedBackground)
    static let tertiarySystemGroupedBackground = Color(UIColor.tertiarySystemGroupedBackground)
    
    // MARK: - Fill Colors
    static let systemFill = Color(UIColor.systemFill)
    static let secondarySystemFill = Color(UIColor.secondarySystemFill)
    static let tertiarySystemFill = Color(UIColor.tertiarySystemFill)
    static let quaternarySystemFill = Color(UIColor.quaternarySystemFill)
    
    // MARK: - Text Colors
    static let label = Color(UIColor.label)
    static let secondaryLabel = Color(UIColor.secondaryLabel)
    static let tertiaryLabel = Color(UIColor.tertiaryLabel)
    static let quaternaryLabel = Color(UIColor.quaternaryLabel)
    static let placeholderText = Color(UIColor.placeholderText)
    static let link = Color(UIColor.link)
    
    // MARK: - Separator Colors
    static let separator = Color(UIColor.separator)
    
    // MARK: - Gray Colors
    static let systemGray = Color(UIColor.systemGray)
}

#endif
