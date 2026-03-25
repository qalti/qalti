//
//  LegacyKeyPress.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 10.03.2025.
//

import SwiftUI

enum KeyHandlingState {
    case handled
    case ignored
}

struct ModifierKey: OptionSet {
    let rawValue: Int
    static let capsLock = ModifierKey(rawValue: 1 << 0)
    static let shift = ModifierKey(rawValue: 1 << 1)
    static let control = ModifierKey(rawValue: 1 << 2)
    static let option = ModifierKey(rawValue: 1 << 3)
    static let command = ModifierKey(rawValue: 1 << 4)
    static let numericPad = ModifierKey(rawValue: 1 << 5)
    static let help = ModifierKey(rawValue: 1 << 6)
    static let function = ModifierKey(rawValue: 1 << 7)
}

#if os(macOS)
import AppKit

extension ModifierKey {
    init(flag: NSEvent.ModifierFlags) {
        var sequense: [ModifierKey] = []
        if flag.contains(.capsLock) {
            sequense.append(.capsLock)
        }
        if flag.contains(.shift) {
            sequense.append(.shift)
        }
        if flag.contains(.control) {
            sequense.append(.control)
        }
        if flag.contains(.option) {
            sequense.append(.option)
        }
        if flag.contains(.command) {
            sequense.append(.command)
        }
        if flag.contains(.numericPad) {
            sequense.append(.numericPad)
        }
        if flag.contains(.help) {
            sequense.append(.help)
        }
        if flag.contains(.function) {
            sequense.append(.function)
        }
        self.init(sequense)
    }
}

struct GlobalKeyPressModifier: ViewModifier {
    let onKeyEvent: (String, ModifierKey) -> KeyHandlingState

    @State private var monitor: Any?
    @State private var window: NSWindow?

    func body(content: Content) -> some View {
        content
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
                    guard self.window?.isKeyWindow == true else { return event }
                    guard let keyString = event.charactersIgnoringModifiers, !keyString.isEmpty else {
                        return event
                    }

                    if onKeyEvent(keyString, ModifierKey(flag: event.modifierFlags)) == .handled {
                        return nil
                    } else {
                        return event
                    }
                }
            }
            .onDisappear {
                if let monitor = monitor {
                    NSEvent.removeMonitor(monitor)
                    self.monitor = nil
                }
            }
            .background(WindowAccessor(window: $window))
    }
}

#else

struct GlobalKeyPressModifier: ViewModifier {

    let onKeyEvent: (String, ModifierKey) -> KeyHandlingState

    func body(content: Content) -> some View {
        content
    }

}

#endif

extension View {
    func onGlobalKeyPress(perform action: @escaping (String, ModifierKey) -> KeyHandlingState) -> some View {
        self.modifier(GlobalKeyPressModifier(onKeyEvent: action))
    }
}
