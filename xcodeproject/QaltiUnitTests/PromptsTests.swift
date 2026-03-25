//
//  PromptsTests.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 27.11.25.
//

import XCTest
@testable import Qalti

final class PromptsTests: XCTestCase {

    // MARK: - Template Structure

    func testSystemPromptTemplateContainsRequiredPlaceholders() {
        let template = Prompts.defaultSystemPromptTemplate

        XCTAssertTrue(template.contains("{test_name}"), "Template must contain {test_name} placeholder")
        XCTAssertTrue(template.contains("{recorded_steps}"), "Template must contain {recorded_steps} placeholder")
        XCTAssertTrue(template.contains("{additional_rules}"), "Template must contain {additional_rules} placeholder")
    }

    func testPromptGeneration_withNilRules_replacesPlaceholdersAndRemovesRulesBlock() throws {
        // SCENARIO: No custom rules are provided.
        let result = try Prompts.generateSystemPrompt(
            testName: "My Test Name",
            recordedSteps: "1. Step One",
            qaltiRules: nil
        )

        XCTAssertTrue(result.contains("My Test Name"))
        XCTAssertTrue(result.contains("        1. Step One"))
        XCTAssertFalse(result.contains("<user_defined_rules>"), "The rules block should be absent when rules are nil.")
        XCTAssertFalse(result.contains("{additional_rules}"), "The placeholder should be replaced with an empty string.")
    }

    func testPromptGeneration_withValidRules_includesRulesBlock() throws {
        // SCENARIO: User provides custom rules.
        let customRules = "Rule 1: Always be awesome.\nRule 2: Never give up."

        let result = try Prompts.generateSystemPrompt(
            testName: "My Test",
            recordedSteps: "1. Step One",
            qaltiRules: customRules
        )

        XCTAssertTrue(result.contains("<user_defined_rules>"))
        XCTAssertTrue(result.contains("        Rule 1: Always be awesome."))
        XCTAssertFalse(result.contains("{additional_rules}"), "The placeholder should be replaced.")
    }

    // MARK: - Updated Format Checks

    func testCommentFormatContainsNewConciseFields() {
        let template = Prompts.defaultSystemPromptTemplate

        // Verify old, verbose fields are GONE
        XCTAssertFalse(template.contains("**Action to perform:**"), "Should no longer use 'Action to perform'")

        // Verify new, structured fields are PRESENT
        XCTAssertTrue(template.contains("**Original Step:**"), "Must contain 'Original Step'")
        XCTAssertTrue(template.contains("**Analysis:**"), "Must contain 'Analysis'")
        XCTAssertTrue(template.contains("**Tip:**"), "Must contain 'Tip'")
    }

    // MARK: - Tool Definitions

    func testToolDefinitionsAreValid() throws {
        let tools = try Prompts.iosFunctionDefinitions()

        // Basic sanity check to ensure we didn't break the JSON structure
        let tapTool = tools.first { $0.name == "tap" }
        XCTAssertNotNil(tapTool)

        // Ensure parameters are defined
        let json = try JSONEncoder().encode(tapTool)
        let string = String(data: json, encoding: .utf8)
        XCTAssertTrue(string?.contains("element_name") ?? false)
    }
}
