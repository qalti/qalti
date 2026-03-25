//
//  PlatformCursor.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 12.06.2025.
//

#if os(macOS)
import AppKit

typealias PlatformCursor = NSCursor

#else

class PlatformCursor {

    static let resizeLeftRight = PlatformCursor()
    static let arrow = PlatformCursor()

    func set() {}
}

#endif
