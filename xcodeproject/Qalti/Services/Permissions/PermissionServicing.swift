//
//  PermissionServicing.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 05.03.26.
//

import Foundation
import Combine

protocol PermissionServicing: ObservableObject {
    var hasDocumentsAccess: Bool { get }
    var isMonitoringPermissions: Bool { get }
    var qaltiFolderPath: String { get }

    // Publishers for SwiftUI views to observe changes
    var hasDocumentsAccessPublisher: AnyPublisher<Bool, Never> { get }
    var isMonitoringPermissionsPublisher: AnyPublisher<Bool, Never> { get }

    func startPermissionMonitoring()
    func stopPermissionMonitoring()
    func refreshPermissionStatus()
}
