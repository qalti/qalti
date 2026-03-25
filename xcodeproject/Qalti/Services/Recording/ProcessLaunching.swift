//
//  ProcessLaunching.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 17.12.25.
//

import Foundation
import Logging

// A protocol to abstract the launching of a Process.
protocol ProcessLaunching {
    func run() throws
    func interrupt()
    func waitUntilExit()
    var isRunning: Bool { get }
}

extension Process: ProcessLaunching {}
