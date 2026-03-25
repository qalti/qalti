//
//  ThrowingIdbManager.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 17.12.25.
//

import XCTest
import GRPC
import IOSurface
@testable import Qalti

class ThrowingIdbManager: IdbManaging {

    // MARK: - File Operations

    func copyFromDevice(udid: String, bundleID: String, filepath: String, destinationPath: String) throws {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "copyFromDevice failed"])
    }

    func copyToDevice(udid: String, filepath: String, bundleID: String, destinationPath: String) throws {
        throw NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "copyToDevice failed"])
    }

    // MARK: - Recording

    func record(udid: String) throws -> RecordCall {
        throw NSError(domain: "Test", code: 4, userInfo: [NSLocalizedDescriptionKey: "record failed"])
    }

    // MARK: - Listings

    func listApps(udid: String) throws -> [(name: String, bundleID: String)] {
        throw NSError(domain: "Test", code: 5, userInfo: [NSLocalizedDescriptionKey: "listApps failed"])
    }

    func listTargets() throws -> [TargetInfo] {
        throw NSError(domain: "Test", code: 6, userInfo: [NSLocalizedDescriptionKey: "listTargets failed"])
    }

    // MARK: - Interaction

    func pressButton(udid: String, buttonType: ButtonType, up: Bool) throws {
        throw NSError(domain: "Test", code: 7, userInfo: [NSLocalizedDescriptionKey: "pressButton failed"])
    }

    func touch(udid: String, x: Int32, y: Int32, up: Bool) throws {
        throw NSError(domain: "Test", code: 8, userInfo: [NSLocalizedDescriptionKey: "touch failed"])
    }

    // MARK: - Connection / Lifecycle

    func isConnected(udid: String) -> Bool {
        return false
    }

    func displayIOSurface(udid: String, completion: @escaping (Result<IOSurface, Error>) -> Void) {
        let error = NSError(domain: "Test", code: 9, userInfo: [NSLocalizedDescriptionKey: "displayIOSurface failed"])
        completion(.failure(error))
    }

    func connect(udid: String, isSimulator: Bool) throws -> Int {
        throw NSError(domain: "Test", code: 10, userInfo: [NSLocalizedDescriptionKey: "connect failed"])
    }

    func disconnect(udid: String) throws {
        throw NSError(domain: "Test", code: 13, userInfo: [NSLocalizedDescriptionKey: "disconnect failed"])
    }

    func bootSimulator(udid: String, verify: Bool) throws {
        throw NSError(domain: "Test", code: 11, userInfo: [NSLocalizedDescriptionKey: "bootSimulator failed"])
    }

    func shutdownSimulator(udid: String) throws {
        throw NSError(domain: "Test", code: 14, userInfo: [NSLocalizedDescriptionKey: "shutdownSimulator failed"])
    }

    // MARK: - Apps

    func installApp(appPath: String, udid: String, makeDebuggable: Bool, completion: @escaping (Result<String, Error>) -> Void) {
        let error = NSError(domain: "Test", code: 12, userInfo: [NSLocalizedDescriptionKey: "installApp failed"])
        completion(.failure(error))
    }
}
