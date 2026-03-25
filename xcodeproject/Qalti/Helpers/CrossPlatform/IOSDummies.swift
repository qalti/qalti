//
//  IOSDummies.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 07.03.2025.
//

#if !os(macOS)
import Foundation

class Process {

    public enum TerminationReason : Int, @unchecked Sendable {
        case exit = 1
        case uncaughtSignal = 2
    }

    class func run(_ url: URL, arguments: [String], terminationHandler: (@Sendable (Process) -> Void)? = nil) throws -> Process {
        throw NSError(domain: "Unsupported platform", code: -1)
    }

    class func launchedProcess(launchPath path: String, arguments: [String]) -> Process {
        return Process()
    }

    var executableURL: URL? = nil
    var arguments: [String]? = []
    var environment: [String : String]? = [:]
    var currentDirectoryURL: URL? = nil
    var launchRequirementData: Data? = nil
    var standardInput: Any? = nil
    var standardOutput: Any? = nil
    var standardError: Any? = nil
    var processIdentifier: Int32 { 0 }
    var isRunning: Bool { false }
    var terminationStatus: Int32 = 0
    var terminationReason: Process.TerminationReason { .exit }
    var terminationHandler: (@Sendable (Process) -> Void)? = nil
    var qualityOfService: QualityOfService = .default
    var launchPath: String? = nil
    var currentDirectoryPath: String = ""

    init() {}

    func run() throws {
        throw NSError(domain: "Unsupported platform", code: -1)
    }

    func interrupt() {}
    func terminate() {}
    func suspend() -> Bool { false }
    func resume() -> Bool { false }
    func waitUntilExit() {}
    func launch() {}

}

extension FileManager {
    var homeDirectoryForCurrentUser: URL { URL(fileURLWithPath: "/") }
}
#endif
