//
//  SettingsService.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 16.12.25.
//

import Foundation
import Combine

/// Manages user-configurable settings for the application, with a focus on video recording.
///
/// This service provides a centralized way to access and modify settings, persisting them to `UserDefaults`.
/// It is designed as an `ObservableObject` to be injected into the SwiftUI environment,
/// allowing views to react to changes and ensuring the code remains testable by avoiding a static singleton.
final class SettingsService: ObservableObject {

    // MARK: - Published Properties

    /// When true, video recordings of test runs will be captured.
    /// - Note: This is the master switch for all video recording functionality.
    /// - User Default Key: `settings.videoRecording.enabled`
    @Published var isVideoRecordingEnabled: Bool {
        didSet {
            userDefaults.set(isVideoRecordingEnabled, forKey: Keys.videoRecordingEnabledKey)
        }
    }

    /// When true, video recordings of **successful** test runs will be automatically deleted.
    /// This helps save disk space by only keeping videos for failed or cancelled tests, which are typically needed for debugging.
    /// - Note: This setting is only effective if `isVideoRecordingEnabled` is `true`.
    /// - User Default Key: `settings.videoRecording.removeOnSuccess`
    @Published var shouldRemoveVideoOnSuccess: Bool {
        didSet {
            userDefaults.set(shouldRemoveVideoOnSuccess, forKey: Keys.shouldRemoveVideoOnSuccessKey)
        }
    }

    // MARK: - Private Properties

    private let userDefaults: UserDefaults

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let videoRecordingEnabledKey = "settings.videoRecording.enabled"
        static let shouldRemoveVideoOnSuccessKey = "settings.videoRecording.removeOnSuccess"
    }

    // MARK: - Initialization

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.isVideoRecordingEnabled = userDefaults.bool(forKey: Keys.videoRecordingEnabledKey)
        self.shouldRemoveVideoOnSuccess = userDefaults.bool(forKey: Keys.shouldRemoveVideoOnSuccessKey)
    }
}
