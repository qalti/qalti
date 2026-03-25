//
//  AllureStepNamingTests.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 27.11.25.
//

import XCTest
@testable import Qalti

final class AllureStepNamingTests: XCTestCase {

    func testExtractsTipFieldAsPrimary() {
        let llmResponse = """
        **Line 2/13:**
        **Original Step:** Tap the button
        **Analysis:** The important action is described here.
        **Tip:** Short tip
        """
        let desc = AllureDescriptionExtractor.extractDescription(from: llmResponse)
        XCTAssertEqual(desc, "Short tip")
    }

    func testExtractsAnalysisFieldAsFallback() {
        let llmResponse = """
        **Line 2/13:**
        **Original Step:** Tap the button
        **Analysis:** This is the analysis text
        """
        let desc = AllureDescriptionExtractor.extractDescription(from: llmResponse)
        XCTAssertEqual(desc, "This is the analysis text")
    }

    func testExtractsOriginalStepAsFinalFallback() {
        let llmResponse = """
        **Line 2/13:**
        **Original Step:** Tap the button to continue
        """
        let desc = AllureDescriptionExtractor.extractDescription(from: llmResponse)
        XCTAssertEqual(desc, "Tap the button to continue")
    }

    func testReturnsNilIfNoKeywordsFound() {
        let llmResponse = "Line 1/5: This text should be ignored now."
        let desc = AllureDescriptionExtractor.extractDescription(from: llmResponse)
        XCTAssertNil(desc, "The old 'Line X: Text' fallback should be gone.")
    }

    func testReturnsNilForEmptyString() {
        XCTAssertNil(AllureDescriptionExtractor.extractDescription(from: ""))
        XCTAssertNil(AllureDescriptionExtractor.extractDescription(from: nil))
    }

    func testCleanForStepName_RemovesTrailingPeriod() {
        let input = "Tap the login button. "
        let result = AllureDescriptionExtractor.cleanForStepName(input)
        XCTAssertEqual(result, "Tap the login button")
    }

    func testCleanForStepName_PreservesClosingParenthesis() {
        let input = "Tap the login button (blue)"
        let result = AllureDescriptionExtractor.cleanForStepName(input)
        XCTAssertEqual(result, "Tap the login button (blue)")
    }

    func testCleanForStepName_PreservesClosingQuote() {
        let input = "Verify the text says \"Success\""
        let result = AllureDescriptionExtractor.cleanForStepName(input)
        XCTAssertEqual(result, "Verify the text says \"Success\"")
    }

    func testCleanForStepName_RemovesPeriodBeforeParenthesis() {
        // This tests a tricky case: "Tap button (blue)."
        let input = "Tap the login button (blue)."
        let result = AllureDescriptionExtractor.cleanForStepName(input)

        // The current implementation will produce "Tap the login button (blue)"
        // because `trimmingCharacters` stops at the first character NOT in the set,
        // which is the closing parenthesis ')'. This is the desired behavior.
        XCTAssertEqual(result, "Tap the login button (blue)")
    }

    func testCleanForStepName_HandlesNil() {
        XCTAssertNil(AllureDescriptionExtractor.cleanForStepName(nil))
    }
}
