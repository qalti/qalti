//
//  MockEnvironmentProvider.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 23.12.25.
//

import Foundation
@testable import Qalti


struct MockEnvironmentProvider: EnvironmentProviding {
    var deviceUDID: String?
    var allVariables: [String: String]
}
