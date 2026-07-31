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

    // MARK: - openApp fails fast on an unresolved app

    /// `openApp` used to hand an unresolved name to the runner as though it were a bundle ID, so a
    /// missing app surfaced as a 60s request timeout instead of an error. It must now answer
    /// immediately and never reach the network.
    func testOpenAppWithUnknownAppReportsNotInstalledWithoutSendingARequest() {
        mockIdbManager.stubbedApps = [(name: "SyncUps", bundleID: "co.kslavnov.SyncUps")]
        let runtime = makeRuntimeWithRealResolver(idbManager: mockIdbManager)

        var response: IOSRuntime.Response?
        runtime.openApp(name: "Notes") { response = $0 }

        let error = try? XCTUnwrap(response?.error)
        XCTAssertNotNil(error, "expected an error response")
        XCTAssertTrue(error?.contains("not installed") ?? false, "error should say it is not installed: \(error ?? "nil")")
        XCTAssertTrue(error?.contains("SyncUps") ?? false, "error should list what is installed: \(error ?? "nil")")
        XCTAssertNil(runtime.capturedRequest, "no request should be sent for an app that isn't there")
    }

    /// Deliberate consequence of the above, recorded so it isn't rediscovered as a bug: when the
    /// app catalogue can't be read at all, `openApp` fails rather than optimistically forwarding a
    /// string that may well be a valid bundle ID. A device-level failure is reported as such, and
    /// is kept distinct from "this app is not installed".
    func testOpenAppWhenCatalogUnavailableFailsFastAndIsNotReportedAsMissingApp() {
        let runtime = makeRuntimeWithRealResolver(idbManager: ThrowingIdbManager())

        var response: IOSRuntime.Response?
        runtime.openApp(name: "com.apple.reminders") { response = $0 }

        let error = try? XCTUnwrap(response?.error)
        XCTAssertNotNil(error, "expected an error response")
        XCTAssertFalse(error?.contains("not installed") ?? true, "device failure must not read as a missing app: \(error ?? "nil")")
        XCTAssertNil(runtime.capturedRequest, "no request should be sent when the catalogue is unreadable")
    }

    /// Unlike `spyRuntime`, whose resolver is never exercised, this builds a runtime over a real
    /// `AppBundleResolver` backed by the given idb stub, so resolution actually runs.
    private func makeRuntimeWithRealResolver(idbManager: IdbManaging) -> SpyIOSRuntime {
        SpyIOSRuntime(
            simulatorID: "test-sim-id",
            idbManager: idbManager,
            errorCapturer: mockErrorCapturer
        )
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
