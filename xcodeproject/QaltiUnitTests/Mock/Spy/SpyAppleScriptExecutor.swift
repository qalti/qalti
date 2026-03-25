//
//  SpyAppleScriptExecutor.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 17.12.25.
//

import XCTest
@testable import Qalti


class SpyAppleScriptExecutor: AppleScriptExecuting {
    var executedScript: String?

    func execute(source: String) -> (success: Bool, error: NSDictionary?) {
        executedScript = source
        return (true, nil)
    }
}
