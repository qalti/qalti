//
//  FakePreviewIdbManager.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 23.12.25.
//

import IOSurface


class FakePreviewIdbManager: IdbManaging {
    // MARK: - File Operations

    func copyFromDevice(udid: String, bundleID: String, filepath: String, destinationPath: String) throws {
    }

    func copyToDevice(udid: String, filepath: String, bundleID: String, destinationPath: String) throws {
    }

    // MARK: - Recording

    func record(udid: String) throws -> RecordCall {
        return FakeRecordCall()
    }

    // MARK: - Listings

    func listApps(udid: String) throws -> [(name: String, bundleID: String)] {
        return []
    }

    func listTargets() throws -> [TargetInfo] {
        return []
    }

    // MARK: - Interaction

    func pressButton(udid: String, buttonType: ButtonType, up: Bool) throws {
    }

    func touch(udid: String, x: Int32, y: Int32, up: Bool) throws {
    }

    // MARK: - Connection / Lifecycle

    func isConnected(udid: String) -> Bool {
        return false
    }

    func displayIOSurface(udid: String, completion: @escaping (Result<IOSurface, Error>) -> Void) {
        completion(.success(IOSurface()))
    }

    func connect(udid: String, isSimulator: Bool) throws -> Int {
        return 0
    }

    func disconnect(udid: String) throws {
    }

    func bootSimulator(udid: String, verify: Bool) throws {
    }

    func shutdownSimulator(udid: String) throws {
    }

    // MARK: - Apps

    func installApp(appPath: String, udid: String, makeDebuggable: Bool, completion: @escaping (Result<String, Error>) -> Void) {
        completion(.success(""))
    }
}
