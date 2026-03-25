//
//  CallbackToken.swift
//  Qalti
//
//  Created by AI Assistant on 02.07.2025.
//

import Foundation

/// A token for callback identification and removal across the app
/// Used by services like CredentialsService and OnboardingManager for type-safe callback management
public struct CallbackToken: Hashable {
    let id = UUID()
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: CallbackToken, rhs: CallbackToken) -> Bool {
        lhs.id == rhs.id
    }
} 
