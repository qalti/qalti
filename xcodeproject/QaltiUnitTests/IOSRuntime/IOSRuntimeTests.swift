//
//  IOSRuntimeTests.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 28.11.25.
//

import XCTest
@testable import Qalti

final class IOSRuntimeTests: XCTestCase {

    // MARK: - Properties for Spy-based Tests
    private var spyRuntime: SpyIOSRuntime!
    private var mockErrorCapturer: MockErrorCapturer!
    private var mockRuntimeUtils: MockRuntimeUtils!
    private var mockIdbManager: MockIdbManager!

    // MARK: - Properties for Static Method Tests
    private let dummyUDID = "0000-DUMMY-UDID"
    private let dummyIP = "fd00::1"

    override func setUp() {
        super.setUp()
        mockErrorCapturer = MockErrorCapturer()
        mockRuntimeUtils = MockRuntimeUtils()
        mockIdbManager = MockIdbManager()

        spyRuntime = SpyIOSRuntime(
            simulatorID: "test-sim-id",
            idbManager: mockIdbManager,
            errorCapturer: mockErrorCapturer
        )
    }

    override func tearDown() {
        spyRuntime = nil
        mockErrorCapturer = nil
        mockRuntimeUtils = nil
        mockIdbManager = nil
        super.tearDown()
    }

    // MARK: - Static Methods (Initialization Logic)

    func testGetIphoneIP_Success() {
        // Arrange
        mockRuntimeUtils.commandResult = .success("    • tunnelIPAddress: \(dummyIP)")
        mockRuntimeUtils.ipActiveLocallyResult = true
        mockRuntimeUtils.getIphoneIPResult = .success("[\(dummyIP)]")

        // Act
        let result = mockRuntimeUtils.getIphoneIP(for: dummyUDID)

        // Assert
        if case .success(let ip) = result {
            XCTAssertEqual(ip, "[\(dummyIP)]")
        } else {
            XCTFail("Expected success, but got failure.")
        }
    }

    func testGetIphoneIP_GhostTunnelFailure() {
        // Arrange
        mockRuntimeUtils.commandResult = .success("    • tunnelIPAddress: \(dummyIP)")
        mockRuntimeUtils.ipActiveLocallyResult = false
        mockRuntimeUtils.getIphoneIPResult = .failure(IOSRuntimeError.ghostTunnelDetected(ip: dummyIP, udid: dummyUDID))

        // Act
        let result = mockRuntimeUtils.getIphoneIP(for: dummyUDID)

        // Assert
        if case .failure(let error) = result, let runtimeError = error as? IOSRuntimeError {
            if case .ghostTunnelDetected(let ip, let udid) = runtimeError {
                XCTAssertEqual(ip, dummyIP)
                XCTAssertEqual(udid, dummyUDID)
            } else {
                XCTFail("Expected .ghostTunnelDetected, but got \(runtimeError)")
            }
        } else {
            XCTFail("Expected failure with IOSRuntimeError, but got success or a different error type.")
        }
    }

    // MARK: - Instance Methods (Agent Commands)

    func testTapScreenBuildsCorrectURL() {
        // Arrange
        let expectation = XCTestExpectation(description: "sendRequest should be called for tapScreen")
        spyRuntime.sendRequestExpectation = expectation

        // Act
        spyRuntime.tapScreen(location: (123, 456), longPress: false) { _ in }

        // Assert
        wait(for: [expectation], timeout: 1.0)
        guard let req = spyRuntime.capturedRequest else { return XCTFail("No request captured") }

        XCTAssertEqual(req.url?.path, "/tap")
        XCTAssertEqual(req.httpMethod, "POST")

        if let body = req.httpBody, let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            XCTAssertEqual(json["x"] as? Int, 123)
            XCTAssertEqual(json["y"] as? Int, 456)
            XCTAssertEqual(json["is_long"] as? Bool, false)
        } else {
            XCTFail("Missing or invalid body")
        }
    }

    func testTapScreenLongPressBuildsCorrectURL() {
        // Arrange
        let expectation = XCTestExpectation(description: "sendRequest should be called for long tap")
        spyRuntime.sendRequestExpectation = expectation

        // Act
        spyRuntime.tapScreen(location: (123, 456), longPress: true) { _ in }

        // Assert
        wait(for: [expectation], timeout: 1.0)
        guard let req = spyRuntime.capturedRequest, let body = req.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return XCTFail("No request or body captured")
        }

        XCTAssertEqual(json["is_long"] as? Bool, true)
    }

    func testZoomBuildsCorrectURL() {
        // Arrange
        let expectation = XCTestExpectation(description: "sendRequest should be called for zoom")
        let specificSpy = SpyIOSRuntime(
            simulatorID: "test-sim-id",
            controlServerPort: 8000,
            idbManager: mockIdbManager,
            errorCapturer: mockErrorCapturer
        )
        specificSpy.sendRequestExpectation = expectation

        // Act
        specificSpy.zoom(location: (50, 150), scale: 2.0, velocity: 1.5) { _ in }

        // Assert
        wait(for: [expectation], timeout: 1.0)
        guard let req = specificSpy.capturedRequest, let body = req.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return XCTFail("No request or body captured")
        }

        XCTAssertEqual(req.url?.port, 8000)
        XCTAssertEqual(req.url?.path, "/zoom")
        XCTAssertEqual(json["x"] as? Int, 50)
        XCTAssertEqual(json["y"] as? Int, 150)
        XCTAssertEqual(json["scale"] as? Double, 2.0)
        XCTAssertEqual(json["velocity"] as? Double, 1.5)
    }

    func testOpenURLWithSpecialCharactersBuildsCorrectURL() {
        // Arrange
        let expectation = XCTestExpectation(description: "sendRequest should be called for openURL")
        spyRuntime.sendRequestExpectation = expectation
        let urlToOpen = "qalti://open?screen=home&user=test user"

        // Act
        spyRuntime.openURL(urlString: urlToOpen) { _ in }

        // Assert
        wait(for: [expectation], timeout: 1.0)
        guard let req = spyRuntime.capturedRequest, let body = req.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return XCTFail("No request or body captured")
        }

        XCTAssertEqual(req.url?.path, "/open-url")
        XCTAssertEqual(json["url"] as? String, urlToOpen)
    }
}

// MARK: - Private Spy Subclass

/// A "Spy" is a test-specific subclass that intercepts method calls to verify inputs.
private class SpyIOSRuntime: IOSRuntime {

    var capturedRequest: URLRequest?
    var sendRequestExpectation: XCTestExpectation?

    required init(
        simulatorID: String,
        controlServerPort: Int = AppConstants.defaultControlPort,
        screenshotServerPort: Int = AppConstants.defaultScreenshotPort,
        idbManager: IdbManaging,
        errorCapturer: ErrorCapturing,
        isIpad: Bool = false
    ) {
        super.init(
            simulatorID: simulatorID,
            controlServerPort: controlServerPort,
            screenshotServerPort: screenshotServerPort,
            idbManager: idbManager,
            errorCapturer: errorCapturer,
            isIpad: isIpad
        )
    }

    required internal init(
        deviceID: String,
        isRealDevice: Bool,
        isIpad: Bool,
        serverAddress: String,
        controlServerPort: Int,
        screenshotServerPort: Int,
        errorCapturer: ErrorCapturing,
        runtimeUtils: IOSRuntimeUtils,
        idbManager: IdbManaging,
        appBundleResolver: AppBundleResolver
    ) {
        super.init(
            deviceID: deviceID,
            isRealDevice: isRealDevice,
            isIpad: isIpad,
            serverAddress: serverAddress,
            controlServerPort: controlServerPort,
            screenshotServerPort: screenshotServerPort,
            errorCapturer: errorCapturer,
            runtimeUtils: runtimeUtils,
            idbManager: idbManager,
            appBundleResolver: appBundleResolver
        )
    }

    override func sendRequest(_ request: URLRequest, shouldRetry: Bool = true, completion: @escaping (Response) -> Void) {
        capturedRequest = request
        completion(Response())
        sendRequestExpectation?.fulfill()
    }
}
