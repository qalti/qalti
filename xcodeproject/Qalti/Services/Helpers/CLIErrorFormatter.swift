//
//  CLIErrorFormatter.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 28.11.25.
//

import Foundation

enum CLIErrorFormatter {

    static func format(error: Error) -> String {
        if let runtimeError = error as? IOSRuntimeError,
           case .ghostTunnelDetected = runtimeError {
            return ghostTunnelErrorMessage(technicalDetail: runtimeError.localizedDescription)
        }

        // You can add more specific formatters here for other known errors.

        return "An unexpected error occurred: \(error.localizedDescription)"
    }

    static func ghostTunnelErrorMessage(technicalDetail: String) -> String {
        return """
        
        -------------------------------------------------
        DEVICE CONNECTION FAILED: GHOST TUNNEL DETECTED
        -------------------------------------------------
        Your Mac can see the device but cannot create a network route to it.
        This is often caused by a VPN, network filter, or a stuck system service.
        
        TO FIX:
        1. Unplug the iPhone.
        2. Run this command in your terminal: sudo pkill -9 remoted
        3. Plug the iPhone back in and wait 15 seconds.
        4. If that fails, restart your Mac.
        
        (Technical Detail: \(technicalDetail))
        -------------------------------------------------
        
        """
    }
}
