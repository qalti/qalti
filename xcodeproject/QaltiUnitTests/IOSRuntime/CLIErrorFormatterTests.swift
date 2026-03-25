//
//  CLIErrorFormatterTests.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 28.11.25.
//

import XCTest
@testable import Qalti

final class CLIErrorFormatterTests: XCTestCase {

    func testFormatsGhostTunnelError() {
        // Arrange
        let ghostError = IOSRuntimeError.ghostTunnelDetected(ip: "fd00::1", udid: "DUMMY-UDID")

        // Act
        let formattedMessage = CLIErrorFormatter.format(error: ghostError)

        // Assert
        XCTAssertTrue(formattedMessage.contains("DEVICE CONNECTION FAILED: GHOST TUNNEL DETECTED"))
        XCTAssertTrue(formattedMessage.contains("sudo pkill -9 remoted"))
        XCTAssertTrue(formattedMessage.contains("(Technical Detail: Network Tunnel Issue"))
    }

    func testFormatsGenericError() {
        // Arrange
        let genericError = NSError(domain: "TestDomain", code: 123, userInfo: [NSLocalizedDescriptionKey: "Something broke"])

        // Act
        let formattedMessage = CLIErrorFormatter.format(error: genericError)

        // Assert
        XCTAssertTrue(formattedMessage.contains("An unexpected error occurred: Something broke"))
    }
}
