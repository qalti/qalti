//
//  CrossPlaftormOpenURL.swift
//  Qalti
//
//  Created by Slava on 17/06/2025.
//

import Foundation

#if os(macOS)
import AppKit

extension URL {
    func openInSystem() {
        NSWorkspace.shared.open(self)
    }
}
#else
import UIKit

extension URL {
    func openInSystem() {
        UIApplication.shared.open(self)
    }
}
#endif
