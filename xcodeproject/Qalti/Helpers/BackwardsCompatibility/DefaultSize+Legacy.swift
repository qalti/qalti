//
//  DefaultSize+Legacy.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 25.06.2025.
//

import SwiftUI

extension Scene {
    func legacy_defaultSize(width: CGFloat, height: CGFloat) -> some Scene {
        if #available(iOS 17.0, macOS 12.0, *) {
            return self.defaultSize(width: width, height: height)
        } else {
            assertionFailure("Focusable is not supported in this version of macOS/iOS")
            return self
        }
    }
}
