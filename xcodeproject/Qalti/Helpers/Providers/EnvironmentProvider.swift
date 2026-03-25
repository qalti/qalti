//
//  EnvironmentProvider.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 23.12.25.
//

import Foundation


protocol EnvironmentProviding {
    /// Retrieves the value of the DEVICE_UDID environment variable.
    var deviceUDID: String? { get }

    /// Provides the complete dictionary of environment variables.
    var allVariables: [String: String] { get }
}

struct SystemEnvironmentProvider: EnvironmentProviding {
    var deviceUDID: String? {
        // The logic for accessing the key is now in one single place.
        ProcessInfo.processInfo.environment["DEVICE_UDID"]
    }

    var allVariables: [String: String] {
        ProcessInfo.processInfo.environment
    }
}
