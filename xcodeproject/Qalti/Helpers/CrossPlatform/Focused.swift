//
//  Focused.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 11.03.2025.
//

import SwiftUI

#if os(macOS)
import AppKit
struct FocusedModifier: ViewModifier {
    let onFocusStateChange: (Bool) -> Void

    @State private var window: NSWindow?
    @State private var keyObserver: Any?
    @State private var resignObserver: Any?

    func body(content: Content) -> some View {
        content
            .legacy_onChange(of: window) { window in
                // Remove existing observers
                if let keyObserver = keyObserver {
                    NotificationCenter.default.removeObserver(keyObserver)
                }
                if let resignObserver = resignObserver {
                    NotificationCenter.default.removeObserver(resignObserver)
                }
                
                guard let window = window else { return }
                
                // Add new observers
                keyObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didBecomeKeyNotification,
                    object: window,
                    queue: .main
                ) { _ in
                    onFocusStateChange(true)
                }
                
                resignObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didResignKeyNotification,
                    object: window,
                    queue: .main
                ) { _ in
                    onFocusStateChange(false)
                }
                
                // Initial state
                onFocusStateChange(window.isKeyWindow)
            }
            .onDisappear {
                if let keyObserver = keyObserver {
                    NotificationCenter.default.removeObserver(keyObserver)
                }
                if let resignObserver = resignObserver {
                    NotificationCenter.default.removeObserver(resignObserver)
                }
            }
            .background(WindowAccessor(window: $window))
    }
}

extension View {
    func onFocusChange(_ onFocusStateChange: @escaping (Bool) -> Void) -> some View {
        modifier(FocusedModifier(onFocusStateChange: onFocusStateChange))
    }
}
#else
extension View {
    func onFocusChange(_ onFocusStateChange: @escaping (Bool) -> Void) -> some View {
        self
    }
}
#endif

