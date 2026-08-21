//
//  RunBlockingErrorTests.swift
//  Qalti
//

import XCTest
@testable import Qalti

/// Cover for which failures interrupt the user with a dialog, and what it says.
///
/// The classification is the load-bearing part: promote too much and people learn to dismiss the
/// dialog unread, promote too little and a stale API key looks like a failing test. A 401 spent
/// this long being mistaken for a model problem precisely because it was rendered as a raw
/// `NSHTTPURLResponse` dump in a one-line strip.
final class RunBlockingErrorTests: XCTestCase {

    // MARK: - Promoted to a dialog

    func test_authenticationFailure_isPromoted_andNamesTheKeySource() throws {
        let blocking = try XCTUnwrap(
            RunBlockingError(from: IOSAgent.Error.authenticationFailed(source: "app Settings (Keychain)"))
        )

        XCTAssertTrue(
            blocking.message.contains("app Settings (Keychain)"),
            "the user cannot fix the right key unless the dialog says which one was used: \(blocking.message)"
        )
        XCTAssertEqual(blocking.remedy, .openSettings)
    }

    /// The failure that prompted this work was reported as "gpt-5-nano failed". It was a 401, and
    /// no model was ever contacted — so the dialog has to actively rule the model out.
    func test_authenticationFailure_saysItIsNotTheModelOrTheTest() throws {
        let blocking = try XCTUnwrap(
            RunBlockingError(from: IOSAgent.Error.authenticationFailed(source: "CLI token (--token/OPENROUTER_API_KEY)"))
        )

        XCTAssertTrue(
            blocking.message.lowercased().contains("not a problem with the test or the selected model"),
            "dialog should rule out the model, which is what people blame first: \(blocking.message)"
        )
    }

    func test_missingKey_isPromoted_andOffersSettings() throws {
        let blocking = try XCTUnwrap(RunBlockingError(from: IOSAgent.Error.missingOpenRouterKey))

        XCTAssertEqual(blocking.remedy, .openSettings)
        XCTAssertFalse(blocking.title.isEmpty)
    }

    /// An exhausted balance is not fixable in Settings, so it must not offer a button that leads
    /// somewhere useless.
    func test_insufficientBalance_isPromoted_butOffersNoSettingsButton() throws {
        let blocking = try XCTUnwrap(RunBlockingError(from: IOSAgent.Error.insufficientBalance))

        XCTAssertEqual(blocking.remedy, .none)
        XCTAssertTrue(blocking.message.contains("openrouter.ai/credits"), "should say where to add funds")
    }

    func test_missingS3Credentials_isPromoted_andOffersSettings() throws {
        let blocking = try XCTUnwrap(RunBlockingError(from: IOSAgent.Error.missingS3Credentials))

        XCTAssertEqual(blocking.remedy, .openSettings)
    }

    // MARK: - Left in the status strip

    /// These are run outcomes, not configuration problems. A modal for an ordinary failing test
    /// would fire constantly and get dismissed reflexively, taking the useful dialogs with it.
    func test_ordinaryRunFailures_areNotPromoted() {
        let ordinary: [IOSAgent.Error] = [
            .unexpectedResponse,
            .unableToInitialisePrompt,
            .unableToSendImage,
            .unableToCreateLogDirectory,
            .unableToWriteLogFile,
            .screenshotWithoutS3URL,
            .missingBase64ImageData,
            .scriptFailed(message: "boom"),
            .backendReportedError(statusCode: 500, message: "upstream exploded")
        ]

        for error in ordinary {
            XCTAssertNil(RunBlockingError(from: error), "should not raise a dialog: \(error)")
        }
    }

    func test_nonAgentErrors_areNotPromoted() {
        let unrelated = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)

        XCTAssertNil(RunBlockingError(from: unrelated))
    }

    // MARK: - Copy quality

    /// Every promoted case interrupts the user, so each one owes them a title, an explanation of
    /// what happened, and a next step — not a restatement of the error enum.
    func test_everyPromotedError_hasActionableCopy() throws {
        let promoted: [IOSAgent.Error] = [
            .authenticationFailed(source: "app Settings (Keychain)"),
            .missingOpenRouterKey,
            .insufficientBalance,
            .missingS3Credentials
        ]

        for error in promoted {
            let blocking = try XCTUnwrap(RunBlockingError(from: error), "\(error) should be promoted")

            XCTAssertFalse(blocking.title.isEmpty, "\(error) needs a title")
            XCTAssertGreaterThan(
                blocking.message.count, 80,
                "\(error) message is too terse to explain anything: \(blocking.message)"
            )
            XCTAssertNotEqual(
                blocking.message, error.localizedDescription,
                "\(error) dialog just repeats the raw error instead of explaining it"
            )
        }
    }
}
