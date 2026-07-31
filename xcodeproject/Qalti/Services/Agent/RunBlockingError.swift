//
//  RunBlockingError.swift
//  Qalti
//

import Foundation

/// A run failure the user has to fix something to get past — a missing or rejected API key,
/// an exhausted balance, missing storage credentials.
///
/// Deliberately narrow. A test that simply fails is normal output and stays in the inline status
/// strip; interrupting with a modal for that would train people to dismiss modals without reading.
/// This type is only for "the run could not proceed until you change a setting", where the inline
/// strip is the wrong surface because the text is long, the cause is not self-evident, and there is
/// somewhere specific to go next.
struct RunBlockingError: Identifiable, Equatable {
    /// What the user should do about it, if there is somewhere to send them.
    enum Remedy: Equatable {
        /// Offer to open Settings, where the relevant credential is entered.
        case openSettings
        /// Nothing to open — the fix is outside the app.
        case none
    }

    let id = UUID()
    let title: String
    let message: String
    let remedy: Remedy

    static func == (lhs: RunBlockingError, rhs: RunBlockingError) -> Bool {
        lhs.title == rhs.title && lhs.message == rhs.message && lhs.remedy == rhs.remedy
    }

    /// Classifies an error thrown by a run. Returns `nil` for ordinary failures, which belong in
    /// the status strip rather than a dialog.
    init?(from error: Swift.Error) {
        guard let agentError = error as? IOSAgent.Error else { return nil }

        switch agentError {
        case .authenticationFailed(let source):
            self.title = "OpenRouter rejected the API key"
            self.message = """
                The key currently in use (from \(source)) was refused by OpenRouter.

                This usually means the key was revoked, mistyped, or belongs to a different \
                service. It is not a problem with the test or the selected model — no model was \
                ever contacted.

                Check the key at openrouter.ai/keys, then re-enter it.
                """
            self.remedy = .openSettings

        case .missingOpenRouterKey:
            self.title = "No OpenRouter API key"
            self.message = """
                Qalti needs an OpenRouter API key to drive a model.

                Neither a CLI token (--token / OPENROUTER_API_KEY) nor a key in Settings is set. \
                Create one at openrouter.ai/keys and add it in Settings.
                """
            self.remedy = .openSettings

        case .insufficientBalance:
            self.title = "OpenRouter balance exhausted"
            self.message = """
                The OpenRouter account backing this key has no credit left, so the run stopped \
                before finishing.

                Add funds at openrouter.ai/credits, then run the test again.
                """
            self.remedy = .none

        case .missingS3Credentials:
            self.title = "AWS S3 credentials missing"
            self.message = """
                This run needs S3 credentials to upload screenshots, and none are configured.

                Add them in Settings, or use a model configuration that sends screenshots inline \
                as base64 instead.
                """
            self.remedy = .openSettings

        case .unableToInitialisePrompt,
             .unexpectedResponse,
             .unableToSendImage,
             .unableToCreateLogDirectory,
             .unableToWriteLogFile,
             .screenshotWithoutS3URL,
             .scriptFailed,
             .backendReportedError,
             .missingBase64ImageData:
            // Run-level failures, not configuration problems. The status strip is the right place.
            return nil
        }
    }
}
