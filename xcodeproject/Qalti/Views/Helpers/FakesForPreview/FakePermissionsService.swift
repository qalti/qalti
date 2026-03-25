//
//  FakePermissionsService.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 05.03.26.
//

import Combine

class FakePermissionService: PermissionServicing {
    var hasDocumentsAccess: Bool = false

    var isMonitoringPermissions: Bool = true

    var qaltiFolderPath: String = ""

    var hasDocumentsAccessPublisher: AnyPublisher<Bool, Never> = .init(Just(false))

    var isMonitoringPermissionsPublisher: AnyPublisher<Bool, Never> = .init(Just(true))

    func startPermissionMonitoring() {
    }

    func stopPermissionMonitoring() {
    }

    func refreshPermissionStatus() {
    }
}
