//
//  EnvironmentSanitizer.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 23.12.25.
//

import Foundation


/// A utility for creating sanitized environments for subprocesses,
/// specifically handling the `DEVICE_UDID` variable to prevent conflicts with Apple's tooling.
struct EnvironmentSanitizer {

    /// Creates a sanitized environment dictionary.
    ///
    /// - Parameters:
    ///   - parentEnvironment: The environment to use as a base, typically `ProcessInfo.processInfo.environment`.
    ///   - isSimulator: A boolean indicating if the target device is a simulator.
    ///   - intendedUDID: The specific UDID of the target device.
    /// - Returns: A new dictionary representing the sanitized environment.
    static func sanitizedEnvironment(
        from parentEnvironment: [String: String],
        isSimulator: Bool,
        intendedUDID: String
    ) -> [String: String] {
        var sanitized = parentEnvironment

        if isSimulator {
            // For simulators, it is safest to completely REMOVE DEVICE_UDID.
            sanitized.removeValue(forKey: "DEVICE_UDID")
        } else {
            // For real devices, we explicitly SET the variable to the intended UDID.
            // This overwrites any incorrect, inherited value.
            sanitized["DEVICE_UDID"] = intendedUDID
        }
        return sanitized
    }
}
