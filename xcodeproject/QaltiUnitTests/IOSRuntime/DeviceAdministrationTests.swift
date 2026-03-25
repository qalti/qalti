//
//  DeviceAdministrationTests.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 28.11.25.
//

import XCTest
@testable import Qalti


final class DeviceAdministrationTests: XCTestCase {

    // --- Mocks for protocols ---
    private var mockIdb: MockIdbManager!
    private var spyAppleScript: SpyAppleScriptExecutor!
    private var mockErrorCapturer: MockErrorCapturer!
    private var mockFileManager: MockFileManager!
    private var mockAppBundleResolver: MockAppBundleResolver!
    private var mockRuntimeUtils: MockRuntimeUtils!

    override func setUp() {
        super.setUp()
        mockErrorCapturer = MockErrorCapturer()
        mockIdb = MockIdbManager()
        spyAppleScript = SpyAppleScriptExecutor()
        mockFileManager = MockFileManager()
        mockAppBundleResolver = MockAppBundleResolver()
        mockRuntimeUtils = MockRuntimeUtils()
    }

    override func tearDown() {
        mockIdb = nil
        spyAppleScript = nil
        mockErrorCapturer = nil
        mockFileManager = nil
        mockAppBundleResolver = nil
        mockRuntimeUtils = nil
        super.tearDown()
    }

    // MARK: - Permission Tests

    func testGrantPermissionConstructsCorrectCommand() {
        // Arrange
        let deviceAdmin = DeviceAdministration(
            deviceId: "SIM-123",
            idbManager: mockIdb,
            appBundleResolver: mockAppBundleResolver,
            runtimeUtils: mockRuntimeUtils,
            appleScriptExecutor: spyAppleScript,
            errorCapturer: mockErrorCapturer,
            fileManager: mockFileManager
        )
        let expectation = self.expectation(description: "runConsoleCommand should be called")
        mockRuntimeUtils.commandExpectation = expectation

        // Act
        deviceAdmin.grantPermission(Permission.photos, forApp: "com.apple.mobilesafari")

        // Assert
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(mockRuntimeUtils.capturedCommand, [
            "xcrun", "simctl", "privacy", "SIM-123", "grant", "photos", "com.apple.mobilesafari"
        ])
    }

    // MARK: - System Time Tests

    func testSetSystemTimeConstructsCorrectAppleScript() {
        // Arrange
        let deviceAdmin = DeviceAdministration(
            deviceId: "SIM-123",
            idbManager: mockIdb,
            appBundleResolver: mockAppBundleResolver,
            runtimeUtils: mockRuntimeUtils,
            appleScriptExecutor: spyAppleScript,
            errorCapturer: mockErrorCapturer,
            fileManager: mockFileManager
        )

        // Act
        deviceAdmin.setSystemTime(to: "14:30")

        // Assert
        XCTAssertNotNil(spyAppleScript.executedScript)
        XCTAssertTrue(spyAppleScript.executedScript?.contains("-setusingnetworktime off") ?? false)
        XCTAssertTrue(spyAppleScript.executedScript?.contains("-settime '14:30:00'") ?? false)
    }

    func testSetNetworkTimeConstructsCorrectAppleScript() {
        // Arrange
        let deviceAdmin = DeviceAdministration(
            deviceId: "SIM-123",
            idbManager: mockIdb,
            appBundleResolver: mockAppBundleResolver,
            runtimeUtils: mockRuntimeUtils,
            appleScriptExecutor: spyAppleScript,
            errorCapturer: mockErrorCapturer,
            fileManager: mockFileManager
        )

        // Act
        deviceAdmin.setNetworkTimeToAuto()

        // Assert
        XCTAssertNotNil(spyAppleScript.executedScript)
        XCTAssertTrue(spyAppleScript.executedScript?.contains("-setusingnetworktime on") ?? false)
    }

    // MARK: - UserDefaults Tests

    func testLoadUserDefaults_Success() throws {
        // Arrange
        let appName = "com.qalti.testapp"
        let deviceAdmin = DeviceAdministration(
            deviceId: "SIM-123",
            idbManager: mockIdb,
            appBundleResolver: mockAppBundleResolver,
            runtimeUtils: mockRuntimeUtils,
            appleScriptExecutor: spyAppleScript,
            errorCapturer: mockErrorCapturer,
            fileManager: mockFileManager
        )

        // 1. Prepare the fake plist data that `loadUserDefaults` will read.
        let fakePrefs = ["isLoggedIn": true, "username": "test"] as [String : Any]
        let fakePlistData = try PropertyListSerialization.data(fromPropertyList: fakePrefs, format: .xml, options: 0)

        // 2. Place the fake data in our mock file system at the path where the code expects to find it.
        let expectedPath = mockFileManager.temporaryDirectory.appendingPathComponent("\(appName).plist")
        mockFileManager.files[expectedPath] = fakePlistData

        // Act
        let loadedPrefs = deviceAdmin.loadUserDefaults(forApp: appName)

        // Assert
        // 3. Verify that `copyFromDevice` was called.
        XCTAssertEqual(mockIdb.copiedFromPath, "Library/Preferences/\(appName).plist")

        // 4. Verify the loaded data matches our fake data.
        XCTAssertEqual(loadedPrefs["isLoggedIn"] as? Bool, true)
        XCTAssertEqual(loadedPrefs["username"] as? String, "test")
    }

    func testSaveUserDefaults_Success() throws {
        // Arrange
        let appName = "com.qalti.testapp"
        let deviceAdmin = DeviceAdministration(
            deviceId: "SIM-123",
            idbManager: mockIdb,
            appBundleResolver: mockAppBundleResolver,
            runtimeUtils: mockRuntimeUtils,
            appleScriptExecutor: spyAppleScript,
            errorCapturer: mockErrorCapturer,
            fileManager: mockFileManager
        )
        let prefsToSave = ["theme": "dark"] as [String : Any]

        // Act
        deviceAdmin.saveUserDefaults(forApp: appName, preferences: prefsToSave)

        // Assert
        // 1. Verify that the correct data was written to our mock file system.
        let expectedPath = mockFileManager.temporaryDirectory.appendingPathComponent("\(appName).plist")
        guard let writtenData = mockFileManager.files[expectedPath] else {
            XCTFail("No data was written to the mock file manager")
            return
        }

        let writtenPrefs = try PropertyListSerialization.propertyList(from: writtenData, options: [], format: nil) as? [String: Any]
        XCTAssertEqual(writtenPrefs?["theme"] as? String, "dark")

        // 2. Verify that `copyToDevice` was called with the correct destination.
        XCTAssertEqual(mockIdb.copiedToPath, "Library/Preferences/")
    }
}
