//
//  DeviceService.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 23.12.25.
//

import Foundation
import SwiftUI

/// A SwiftUI-friendly wrapper around IdbManaging.
class DeviceService: ObservableObject {
    let manager: IdbManaging

    init(manager: IdbManaging) {
        self.manager = manager
    }
}
