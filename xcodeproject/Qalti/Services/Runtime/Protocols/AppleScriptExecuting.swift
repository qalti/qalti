//
//  AppleScriptExecuting.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 28.11.25.
//

import Foundation

protocol AppleScriptExecuting {
    func execute(source: String) -> (success: Bool, error: NSDictionary?)
}

// Create a real implementation that wraps NSAppleScript.
struct LiveAppleScriptExecutor: AppleScriptExecuting {
    func execute(source: String) -> (success: Bool, error: NSDictionary?) {
        #if os(macOS)
        var errorDict: NSDictionary?
        if let script = NSAppleScript(source: source) {
            let eventDescriptor = script.executeAndReturnError(&errorDict)
            return (eventDescriptor != nil, errorDict)
        }
        return (false, ["error": "Failed to create NSAppleScript object"])
        #else
        return (false, ["error": "AppleScript is not supported on this platform"])
        #endif
    }
}
