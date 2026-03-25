//
//  PermissionServiceTests.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 05.03.26.
//

import XCTest
import Combine
@testable import Qalti

class PermissionServiceTests: XCTestCase {

    private var sut: PermissionService!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        sut = PermissionService()
        cancellables = []
    }

    override func tearDown() {
        sut = nil
        cancellables = nil
        super.tearDown()
    }

    func test_initialState_isMonitoringIsFalse() {
        // Assert
        XCTAssertFalse(sut.isMonitoringPermissions, "PermissionService should not be monitoring initially.")
    }

    func test_startPermissionMonitoring_setsIsMonitoringToTrue() {
        // Act
        sut.startPermissionMonitoring()

        // Assert
        XCTAssertTrue(sut.isMonitoringPermissions, "isMonitoringPermissions should be true after starting.")
    }

    func test_stopPermissionMonitoring_setsIsMonitoringToFalse() {
        // Arrange
        sut.startPermissionMonitoring()
        XCTAssertTrue(sut.isMonitoringPermissions, "Precondition: isMonitoringPermissions should be true.")

        // Act
        sut.stopPermissionMonitoring()

        // Assert
        XCTAssertFalse(sut.isMonitoringPermissions, "isMonitoringPermissions should be false after stopping.")
    }

    func test_hasDocumentsAccessPublisher_emitsValueOnChange() {
        // Arrange
        let expectation = XCTestExpectation(description: "Receive value from hasDocumentsAccessPublisher")
        var receivedValue: Bool?

        sut.hasDocumentsAccessPublisher
            .sink { value in
                receivedValue = value
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Act
        sut.hasDocumentsAccess = true

        // Assert
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedValue, true)
    }
}
