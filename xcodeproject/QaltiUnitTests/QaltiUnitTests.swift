//
//  QaltiUnitTests.swift
//  QaltiUnitTests
//
//  Created by Pavel Akhrameev on 05.11.25.
//

import XCTest
import CoreGraphics
@testable import Qalti

final class QaltiUnitTests: XCTestCase {
    
    private var requestBuilder: IOSRuntimeRequestBuilder!

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
    }

    func testPointOutRelativeCoordinatesConvertToPixels() {
        let coords = UIElementLocator.PointOutResponse.Coordinates(x: 0.5, y: 0.25)
        let result = CommandExecutorToolsForAgent.pixelCoordinates(
            relativeCoordinates: coords,
            originalSize: CGSize(width: 200, height: 400)
        )

        XCTAssertEqual(result?.x, 100)
        XCTAssertEqual(result?.y, 100)
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        measure {
            // Put the code you want to measure the time of here.
        }
    }

}
