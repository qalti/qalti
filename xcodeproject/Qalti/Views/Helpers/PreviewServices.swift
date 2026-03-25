//
//  PreviewServices.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 19.12.25.
//

import Foundation


@MainActor
enum PreviewServices {
    static let errorCapturer = ErrorCapturerService()
    static let credentials = CredentialsService(errorCapturer: errorCapturer)
    static let onboarding = OnboardingManager()

    static let fakeIdb = FakePreviewIdbManager()
    static let mockSettings = SettingsService()
    static let mockRunStorage = RunStorage()
    static func makeSuiteRunner() -> TestSuiteRunner {
        return TestSuiteRunner(
            documentsURL: URL(fileURLWithPath: "/tmp/qalti-preview-docs"), // A dummy URL is fine for previews
            runStorage: mockRunStorage,
            credentialsService: credentials,
            idbManager: fakeIdb,
            errorCapturer: errorCapturer
        )
    }
}
