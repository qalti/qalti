//
//  MockIdbManager.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 17.12.25.
//

import XCTest
import GRPC
import IOSurface
@testable import Qalti

class MockIdbManager: IdbManaging {

    // Spies (Capture inputs)
    var copiedFromPath: String?
    var copiedToPath: String?
    var recordUdid: String?
    var connectedUdid: String?
    var disconnectedUdid: String?
    var shutdownUdid: String?
    var pressedButton: ButtonType?
    var touchedCoordinates: (x: Int32, y: Int32)?
    var installedAppPath: String?
    var bootedUdid: String?

    // Stubs (Configure outputs)
    var stubbedApps: [(name: String, bundleID: String)] = []
    var stubbedTargets: [TargetInfo] = []
    var stubbedIsConnected: Bool = true
    var stubbedConnectionPort: Int = 1234
    var stubbedInstallResult: Result<String, Error> = .success("com.mock.app")

    // MARK: - File Operations

    func copyFromDevice(udid: String, bundleID: String, filepath: String, destinationPath: String) throws {
        copiedFromPath = filepath
    }

    func copyToDevice(udid: String, filepath: String, bundleID: String, destinationPath: String) throws {
        copiedToPath = destinationPath
    }

    // MARK: - Recording

    func record(udid: String) throws -> RecordCall {
        recordUdid = udid
        return MockRecordCall()
    }

    // MARK: - Listings

    func listApps(udid: String) throws -> [(name: String, bundleID: String)] {
        return stubbedApps
    }

    func listTargets() throws -> [TargetInfo] {
        return stubbedTargets
    }

    // MARK: - Interaction

    func pressButton(udid: String, buttonType: ButtonType, up: Bool) throws {
        pressedButton = buttonType
    }

    func touch(udid: String, x: Int32, y: Int32, up: Bool) throws {
        touchedCoordinates = (x, y)
    }

    // MARK: - Connection / Lifecycle

    func isConnected(udid: String) -> Bool {
        return stubbedIsConnected
    }

    func connect(udid: String, isSimulator: Bool) throws -> Int {
        connectedUdid = udid
        return stubbedConnectionPort
    }

    func disconnect(udid: String) throws {
        disconnectedUdid = udid
    }

    func bootSimulator(udid: String, verify: Bool) throws {
        bootedUdid = udid
    }

    func shutdownSimulator(udid: String) throws {
        shutdownUdid = udid
    }

    func displayIOSurface(udid: String, completion: @escaping (Result<IOSurface, Error>) -> Void) {
        // IOSurface cannot be easily instantiated in a mock without underlying C-API calls.
        // We generally return failure here for basic mocks, or use a specific Fake if needing to test UI rendering.
        let error = NSError(domain: "MockIdbManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "IOSurface mocking not implemented"])
        completion(.failure(error))
    }

    // MARK: - Apps

    func installApp(appPath: String, udid: String, makeDebuggable: Bool, completion: @escaping (Result<String, Error>) -> Void) {
        installedAppPath = appPath
        completion(stubbedInstallResult)
    }
}
