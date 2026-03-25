//
//  IOSRuntimeRequestBuilderTests.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 05.11.25.
//

import XCTest
@testable import Qalti

final class IOSRuntimeRequestBuilderTests: XCTestCase {
    
    // MARK: - Properties
    
    // We declare a property for the class we are testing.
    private var requestBuilder: IOSRuntimeRequestBuilder!
    
    // MARK: - Test Lifecycle
    
    override func setUp() {
        super.setUp()
        // This method is called before each test function runs.
        // We create a fresh instance of the builder here to ensure
        // each test starts in a clean, isolated state.
        requestBuilder = IOSRuntimeRequestBuilder(serverAddress: "localhost", controlServerPort: 8000)
    }
    
    override func tearDown() {
        // This method is called after each test function runs.
        // We release the builder instance to clean up.
        requestBuilder = nil
        super.tearDown()
    }
    
    // MARK: - Command Request Tests

    func test_buildRequest_forTap() throws {
        let request = try XCTUnwrap(requestBuilder.buildRequest(for: .tap(x: 100, y: 200, isLong: false)))
        XCTAssertEqual(request.url?.path, "/tap")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Qalti-Wait"), "false")
        let body = try decodeBody(request)
        XCTAssertEqual(body["x"] as? Int, 100)
        XCTAssertEqual(body["y"] as? Int, 200)
        XCTAssertEqual(body["is_long"] as? Bool, false)
    }

    func test_buildRequest_forTap_longTrue() throws {
        let request = try XCTUnwrap(requestBuilder.buildRequest(for: .tap(x: 150, y: 250, isLong: true)))
        let body = try decodeBody(request)
        XCTAssertEqual(body["is_long"] as? Bool, true)
    }

    func test_buildRequest_forZoom() throws {
        let request = try XCTUnwrap(requestBuilder.buildRequest(for: .zoom(x: 50, y: 150, scale: 2.0, velocity: 1.5)))
        XCTAssertEqual(request.url?.path, "/zoom")
        let body = try decodeBody(request)
        XCTAssertEqual(body["x"] as? Int, 50)
        XCTAssertEqual(body["y"] as? Int, 150)
        XCTAssertEqual(body["scale"] as? Double, 2.0)
        XCTAssertEqual(body["velocity"] as? Double, 1.5)
    }

    func test_buildRequest_forCreep() throws {
        let request = try XCTUnwrap(requestBuilder.buildRequest(for: .creep(x: 30, y: 40, direction: "down", amount: 100)))
        XCTAssertEqual(request.url?.path, "/creep")
        let body = try decodeBody(request)
        XCTAssertEqual(body["direction"] as? String, "down")
        XCTAssertEqual(body["amount"] as? Int, 100)
    }

    func test_buildRequest_forInput_preservesSpecialCharacters() throws {
        let text = "Hello (world)! & test \u{7F}"
        let request = try XCTUnwrap(requestBuilder.buildRequest(for: .input(text: text)))
        let body = try decodeBody(request)
        XCTAssertEqual(body["text"] as? String, text)
    }

    func test_buildRequest_forOpenURLWithSpecialCharacters() throws {
        let urlString = "qalti://open?screen=home&user=test user"
        let request = try XCTUnwrap(requestBuilder.buildRequest(for: .openURL(urlString: urlString)))
        XCTAssertEqual(request.url?.path, "/open-url")
        let body = try decodeBody(request)
        XCTAssertEqual(body["url"] as? String, urlString)
    }

    func test_buildRequest_forOpenApp() throws {
        let request = try XCTUnwrap(requestBuilder.buildRequest(for: .openApp(bundleID: "com.apple.mobilesafari", launchArguments: nil, launchEnvironment: nil)))
        XCTAssertEqual(request.url?.path, "/open-app")
        let body = try decodeBody(request)
        XCTAssertEqual(body["bundle_id"] as? String, "com.apple.mobilesafari")
        XCTAssertNil(body["launch_arguments"])
        XCTAssertNil(body["launch_environment"])
    }

    func test_buildRequest_forOpenApp_withLaunchArguments() throws {
        let args = ["-FIRDebugEnabled", "arg2"]
        let request = try XCTUnwrap(requestBuilder.buildRequest(for: .openApp(bundleID: "com.qalti.app", launchArguments: args, launchEnvironment: nil)))
        let body = try decodeBody(request)
        XCTAssertEqual(body["bundle_id"] as? String, "com.qalti.app")
        XCTAssertEqual(body["launch_arguments"] as? [String], args)
    }

    func test_buildRequest_forOpenApp_withLaunchEnvironment() throws {
        let env = ["isUITest": "true"]
        let request = try XCTUnwrap(requestBuilder.buildRequest(for: .openApp(bundleID: "com.qalti.app", launchArguments: nil, launchEnvironment: env)))
        let body = try decodeBody(request)
        XCTAssertEqual(body["launch_environment"] as? [String: String], env)
    }

    func test_buildRequest_forOpenApp_withBothArgumentsAndEnvironment() throws {
        let args = ["-debug"]
        let env = ["network_mocking": "enabled"]
        let request = try XCTUnwrap(requestBuilder.buildRequest(for: .openApp(bundleID: "com.qalti.app", launchArguments: args, launchEnvironment: env)))
        let body = try decodeBody(request)
        XCTAssertEqual(body["launch_arguments"] as? [String], args)
        XCTAssertEqual(body["launch_environment"] as? [String: String], env)
    }

    func test_buildRequest_forOpenApp_withEmptyCollections() throws {
        let request = try XCTUnwrap(requestBuilder.buildRequest(for: .openApp(bundleID: "com.qalti.app", launchArguments: [], launchEnvironment: [:])))
        let body = try decodeBody(request)
        XCTAssertEqual(body["launch_arguments"] as? [String], [])
        XCTAssertEqual(body["launch_environment"] as? [String: String], [:])
    }

    func test_buildRequest_forSimpleCommands() {
        for command in [RunnerCommand.shake, .clearInputField] {
            let request = requestBuilder.buildRequest(for: command)
            XCTAssertEqual(request?.httpMethod, "POST")
            XCTAssertNil(request?.httpBody)
        }
    }

    func test_buildRequest_forGetCommands_setsMethodGet() {
        let commands: [(RunnerCommand, String)] = [
            (.getHierarchy, "/hierarchy"),
            (.hasKeyboard, "/has-keyboard"),
            (.getScreenInfo, "/screen-info"),
        ]
        for (command, path) in commands {
            let request = requestBuilder.buildRequest(for: command, waitForCompletion: true)
            XCTAssertEqual(request?.httpMethod, "GET")
            XCTAssertEqual(request?.url?.path, path)
            XCTAssertEqual(request?.value(forHTTPHeaderField: "X-Qalti-Wait"), "true")
        }
    }

    func test_buildRequest_withWaitForCompletionTrue_setsHeader() {
        let request = requestBuilder.buildRequest(for: .getScreenInfo, waitForCompletion: true)
        XCTAssertEqual(request?.value(forHTTPHeaderField: "X-Qalti-Wait"), "true")
    }
}

// MARK: - Helpers

private func decodeBody(_ request: URLRequest) throws -> [String: Any] {
    let data = try XCTUnwrap(request.httpBody)
    let json = try JSONSerialization.jsonObject(with: data, options: [])
    return try XCTUnwrap(json as? [String: Any])
}
