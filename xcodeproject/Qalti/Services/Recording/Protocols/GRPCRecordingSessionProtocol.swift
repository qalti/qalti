//
//  GRPCRecordingSessionProtocol.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 18.12.25.
//

import Foundation


/// Defines the interface for a screen recording session that uses a gRPC stream.
protocol GRPCRecordingSessionProtocol {
    /// The URL where the video output will be saved.
    var outputURL: URL { get }

    /// Starts the screen recording process in the background.
    /// - Parameter udid: The UDID of the target device or simulator.
    func start(udid: String) throws

    /// Stops the screen recording process gracefully.
    func stop() async
}
