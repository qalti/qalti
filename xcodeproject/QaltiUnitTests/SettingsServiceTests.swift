//
//  SettingsServiceTests.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 16.12.25.
//

import XCTest
@testable import Qalti

class MockUserDefaults: UserDefaults {
    private var storage: [String: Any] = [:]

    override func bool(forKey defaultName: String) -> Bool {
        return storage[defaultName] as? Bool ?? false
    }

    override func set(_ value: Bool, forKey defaultName: String) {
        storage[defaultName] = value
    }
}

class SettingsServiceTests: XCTestCase {

    var userDefaults: MockUserDefaults!
    var settingsService: SettingsService!

    override func setUp() {
        super.setUp()
        userDefaults = MockUserDefaults()
        settingsService = SettingsService(userDefaults: userDefaults)
    }

    func test_initializesWithUserDefaultsValues() {
        // Arrange: Set values in UserDefaults before initialization
        userDefaults.set(true, forKey: "settings.videoRecording.enabled")
        userDefaults.set(true, forKey: "settings.videoRecording.removeOnSuccess")

        // Act: Re-initialize the service to make it read the new values
        settingsService = SettingsService(userDefaults: userDefaults)

        // Assert: The service properties should match what was in UserDefaults
        XCTAssertTrue(settingsService.isVideoRecordingEnabled)
        XCTAssertTrue(settingsService.shouldRemoveVideoOnSuccess)
    }

    func test_initializesWithDefaultFalseValuesWhenKeysAreMissing() {
        // Arrange: UserDefaults is empty

        // Act: Initialize the service
        settingsService = SettingsService(userDefaults: MockUserDefaults())

        // Assert: Properties should default to false
        XCTAssertFalse(settingsService.isVideoRecordingEnabled)
        XCTAssertFalse(settingsService.shouldRemoveVideoOnSuccess)
    }

    func test_settingIsVideoRecordingEnabled_savesToUserDefaults() {
        // Act: Change a property on the service
        settingsService.isVideoRecordingEnabled = true

        // Assert: The new value should be saved to our mock UserDefaults
        XCTAssertTrue(userDefaults.bool(forKey: "settings.videoRecording.enabled"))
    }

    func test_settingShouldRemoveVideoOnSuccess_savesToUserDefaults() {
        // Act: Change a property on the service
        settingsService.shouldRemoveVideoOnSuccess = true

        // Assert: The new value should be saved to our mock UserDefaults
        XCTAssertTrue(userDefaults.bool(forKey: "settings.videoRecording.removeOnSuccess"))
    }
}
