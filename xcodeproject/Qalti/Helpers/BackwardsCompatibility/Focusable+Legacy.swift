//
//  Focusable+Legacy.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 11.03.2025.
//

import SwiftUI

extension View {
    func legacy_focusable(_ isFocusable: Bool = true) -> some View {
        if #available(iOS 17.0, macOS 12.0, *) {
            return self.focusable(isFocusable)
        } else {
            assertionFailure("Focusable is not supported in this version of macOS/iOS")
            return self
        }
    }
}
