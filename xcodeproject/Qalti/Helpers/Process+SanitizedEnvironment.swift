//
//  Process+SanitizedEnvironment.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 23.12.25.
//

import Foundation


extension Process {
    /// A convenience setter to apply a sanitized environment to the process.
    func setSanitizedEnvironment(
        isSimulator: Bool,
        intendedUDID: String,
        environment: EnvironmentProviding = SystemEnvironmentProvider()
    ) {
        self.environment = EnvironmentSanitizer.sanitizedEnvironment(
            from: environment.allVariables,
            isSimulator: isSimulator,
            intendedUDID: intendedUDID
        )
    }
}
