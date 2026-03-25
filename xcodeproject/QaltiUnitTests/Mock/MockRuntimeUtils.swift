//
//  MockRuntimeUtils.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 17.12.25.
//

import XCTest
@testable import Qalti


class MockRuntimeUtils: IOSRuntimeUtilsProviding {
    var capturedCommand: [String]?
    var commandExpectation: XCTestExpectation?
    var commandResult: Result<String, Error> = .success("")

    var ipActiveLocallyExpectation: XCTestExpectation?
    var ipActiveLocallyResult: Bool = false

    var getIphoneIPResult: Result<String, Error> = .failure(
        NSError(domain: "MockRuntimeUtils", code: 0, userInfo: [NSLocalizedDescriptionKey: "Result not set for mock"])
    )
    var capturedGetIphoneIPDeviceID: String?

    func getIphoneIP(for deviceID: String) -> Result<String, Error> {
        capturedGetIphoneIPDeviceID = deviceID
        return getIphoneIPResult
    }

    func runConsoleCommand(command: [String], timeout: TimeInterval?) -> Result<String, Error> {
        capturedCommand = command
        commandExpectation?.fulfill()
        return commandResult
    }

    func isIPActiveLocally(_ ipAddress: String) -> Bool {
        ipActiveLocallyExpectation?.fulfill()
        return ipActiveLocallyResult
    }
}
