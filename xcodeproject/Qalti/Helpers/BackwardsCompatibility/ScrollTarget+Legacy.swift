//
//  ScrollTarget+Legacy.swift
//  Qalti
//
//  Created by Slava on 17/06/2025.
//

import SwiftUI

extension View {
    func legacy_scrollTargetLayout(isEnabled: Bool = true) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            return self.scrollTargetLayout(isEnabled: isEnabled)
        } else {
            return self
        }
    }
    
    func legacy_scrollPosition(id: Binding<(some Hashable)?>, anchor: UnitPoint? = nil) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            return self.scrollPosition(id: id, anchor: anchor)
        } else {
            return self
        }
    }
}
