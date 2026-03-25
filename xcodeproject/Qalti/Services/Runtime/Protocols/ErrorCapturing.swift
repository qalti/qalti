//
//  ErrorCapturing.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 28.11.25.
//

import Foundation

public protocol ErrorCapturing {
    func capture(error: Error)
}
