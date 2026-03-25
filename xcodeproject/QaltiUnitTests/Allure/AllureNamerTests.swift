//
//  AllureNamerTests.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 03.12.25.
//

import XCTest
@testable import Qalti

final class AllureNamerTests: XCTestCase {

    func testScreenshotName_forSingleImage() {
        let name = AllureNamer.screenshotName(step: 5, imageIndex: 0, totalImagesInMessage: 1)
        XCTAssertEqual(name, "Screenshot after Step 5")
    }

    func testScreenshotName_forMultipleImages() {
        // First image in a set of three
        let name1 = AllureNamer.screenshotName(step: 5, imageIndex: 0, totalImagesInMessage: 3)
        XCTAssertEqual(name1, "Screenshot after Step 5 (1)")

        // Second image
        let name2 = AllureNamer.screenshotName(step: 5, imageIndex: 1, totalImagesInMessage: 3)
        XCTAssertEqual(name2, "Screenshot after Step 5 (2)")
    }
}
