//
//  AppExecutionMode.swift.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 16.12.25.
//

import Foundation

/// Defines the context in which the application is running.
/// This allows services to tailor their initialization and behavior.
public enum AppExecutionMode {
    /// The standard graphical user interface application.
    case gui

    /// The command-line interface tool.
    case cli
}
