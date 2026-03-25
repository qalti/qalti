//
//  IdbManaging.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 28.11.25.
//

import Foundation
import GRPC
import IOSurface

protocol IdbManaging {
    // File operations
    func copyFromDevice(udid: String, bundleID: String, filepath: String, destinationPath: String) throws
    func copyToDevice(udid: String, filepath: String, bundleID: String, destinationPath: String) throws

    // Test/Target operations
    func record(udid: String) throws -> RecordCall
    func listApps(udid: String) throws -> [(name: String, bundleID: String)]
    func listTargets() throws -> [TargetInfo]

    // Interaction
    func pressButton(udid: String, buttonType: ButtonType, up: Bool) throws
    func touch(udid: String, x: Int32, y: Int32, up: Bool) throws

    // Connection/Display
    func isConnected(udid: String) -> Bool
    func displayIOSurface(udid: String, completion: @escaping (Result<IOSurface, Error>) -> Void)

    // Lifecycle
    func connect(udid: String, isSimulator: Bool) throws -> Int
    func disconnect(udid: String) throws
    func bootSimulator(udid: String, verify: Bool) throws
    func shutdownSimulator(udid: String) throws

    // Apps operations
    func installApp(
        appPath: String,
        udid: String,
        makeDebuggable: Bool,
        completion: @escaping (Result<String, Error>) -> Void
    )
}

extension IdbManager: IdbManaging {}
