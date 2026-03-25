//
//  DataExtensionsTests.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 16.11.25.
//

import XCTest
@testable import Qalti

final class DataExtensionsTests: XCTestCase {

    // A tiny, valid 1x1 pixel black PNG image encoded in Base64.
    private let validBase64ImageString = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="

    private var expectedImageData: Data!

    override func setUp() {
        super.setUp()
        expectedImageData = Data(base64Encoded: validBase64ImageString)!
        XCTAssertNotNil(expectedImageData, "Test setup failed: Could not decode the sample Base64 string.")
    }

    // MARK: - Success Scenarios

    func testInit_WithValidDataURL_Succeeds() {
        // Arrange
        let dataURLString = "data:image/png;base64," + validBase64ImageString

        // Act
        let resultData = Data(fromImageDataString: dataURLString)

        // Assert
        XCTAssertNotNil(resultData, "The initializer should successfully decode a valid Data URL.")
        XCTAssertEqual(resultData, expectedImageData, "The decoded data should match the expected image data.")
    }

    func testInit_WithRawBase64String_Succeeds() {
        // Arrange
        let rawBase64String = validBase64ImageString

        // Act
        let resultData = Data(fromImageDataString: rawBase64String)

        // Assert
        XCTAssertNotNil(resultData, "The initializer should succeed as a fallback for a raw Base64 string.")
        XCTAssertEqual(resultData, expectedImageData, "The decoded data should match the expected image data.")
    }

    func testInit_WithValidDataURL_WithJpegType_Succeeds() {
        // Arrange
        let dataURLString = "data:image/jpeg;base64," + validBase64ImageString

        // Act
        let resultData = Data(fromImageDataString: dataURLString)

        // Assert
        XCTAssertNotNil(resultData, "The initializer should handle different image mime types like jpeg.")
        XCTAssertEqual(resultData, expectedImageData)
    }

    // MARK: - Failure Scenarios

    func testInit_WithEmptyString_FailsAndReturnsNil() {
        // Arrange
        let emptyString = ""

        // Act
        let resultData = Data(fromImageDataString: emptyString)

        // Assert
        XCTAssertNil(resultData, "The initializer should return nil for an empty string.")
    }

    func testInit_WithInvalidPrefix_FailsAndReturnsNil() {
        // Arrange
        // It has the prefix, but it's not a valid Base64 string.
        let invalidDataURL = "data:image/jpeg;base64,not-a-valid-base64-string"

        // Act
        let resultData = Data(fromImageDataString: invalidDataURL)

        // Assert
        XCTAssertNil(resultData, "The initializer should return nil if the Base64 content is invalid.")
    }

    func testInit_WithNonBase64String_FailsAndReturnsNil() {
        // Arrange
        let nonBase64String = "Hello, world!"

        // Act
        let resultData = Data(fromImageDataString: nonBase64String)

        // Assert
        XCTAssertNil(resultData, "The initializer should return nil for a plain string that is not Base64.")
    }

    func testInit_WithCorruptBase64String_FailsAndReturnsNil() {
        // Arrange
        // A Base64 string with invalid characters or incorrect padding.
        let corruptBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=%%%%"

        // Act
        let resultData = Data(fromImageDataString: corruptBase64)

        // Assert
        XCTAssertNil(resultData, "The initializer should return nil for a corrupt Base64 string.")
    }

    func testInit_WithValidBase64_ButNotAnImage_FailsAndReturnsNil() {
        // Arrange
        // "Hello World" encoded in Base64 is "SGVsbG8gV29ybGQ=". This is valid Base64, but not a valid image file.
        let nonImageDataString = "SGVsbG8gV29ybGQ="

        // Act
        let resultData = Data(fromImageDataString: nonImageDataString)

        // Assert
        XCTAssertNil(resultData, "The initializer should return nil if the decoded data is not a valid image, thanks to the PlatformImage check.")
    }
}
