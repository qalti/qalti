//
//  IOSRuntimeUtilsProviding.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 17.12.25.
//

import Foundation

protocol IOSRuntimeUtilsProviding {
    @discardableResult
    func runConsoleCommand(command: [String], timeout: TimeInterval?) -> Result<String, Error>

    func getIphoneIP(for deviceID: String) -> Result<String, Error>
    func isIPActiveLocally(_ ipAddress: String) -> Bool
}
