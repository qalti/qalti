//
//  EnvironmentSanitizerTests.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 23.12.25.
//

import XCTest
@testable import Qalti


class EnvironmentSanitizerTests: XCTestCase {

    func test_sanitizedEnvironment_forSimulator_removesDeviceUDID() {
        // Arrange
        let parentEnv = ["DEVICE_UDID": "some_real_udid", "PATH": "/usr/bin"]

        // Act
        let sanitized = EnvironmentSanitizer.sanitizedEnvironment(
            from: parentEnv,
            isSimulator: true,
            intendedUDID: "simulator_udid"
        )

        // Assert
        XCTAssertNil(sanitized["DEVICE_UDID"])
        XCTAssertEqual(sanitized["PATH"], "/usr/bin")
    }

    func test_sanitizedEnvironment_forRealDevice_overwritesExistingDeviceUDID() {
        // Arrange
        let parentEnv = ["DEVICE_UDID": "wrong_udid", "PATH": "/usr/bin"]
        let intendedUDID = "correct_real_udid"

        // Act
        let sanitized = EnvironmentSanitizer.sanitizedEnvironment(
            from: parentEnv,
            isSimulator: false,
            intendedUDID: intendedUDID
        )

        // Assert
        XCTAssertEqual(sanitized["DEVICE_UDID"], intendedUDID)
        XCTAssertEqual(sanitized["PATH"], "/usr/bin")
    }

    func test_sanitizedEnvironment_forRealDevice_addsDeviceUDIDIfNotPresent() {
        // Arrange
        let parentEnv = ["PATH": "/usr/bin"] // No DEVICE_UDID
        let intendedUDID = "correct_real_udid"

        // Act
        let sanitized = EnvironmentSanitizer.sanitizedEnvironment(
            from: parentEnv,
            isSimulator: false,
            intendedUDID: intendedUDID
        )

        // Assert
        XCTAssertEqual(sanitized["DEVICE_UDID"], intendedUDID)
        XCTAssertEqual(sanitized["PATH"], "/usr/bin")
    }

    func test_sanitizedEnvironment_forSimulator_whenDeviceUDIDisNotPresent() {
        // Arrange
        let parentEnv = ["PATH": "/usr/bin"] // No DEVICE_UDID

        // Act
        let sanitized = EnvironmentSanitizer.sanitizedEnvironment(
            from: parentEnv,
            isSimulator: true,
            intendedUDID: "any_simulator_udid"
        )

        // Assert
        XCTAssertNil(sanitized["DEVICE_UDID"])
        XCTAssertEqual(sanitized["PATH"], "/usr/bin")
        XCTAssertEqual(sanitized.count, 1)
    }
}
