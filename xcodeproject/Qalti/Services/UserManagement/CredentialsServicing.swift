//
//  CredentialsServicing.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 06.03.26.
//

import Foundation
import Combine

protocol CredentialsServicing: ObservableObject {
    var hasCredentials: Bool { get }
    var openRouterKey: String? { get }
    var s3Settings: S3Settings? { get }
    var bearer: String? { get }

    func setApiKeyForCLI(_ key: String)
    func setOpenRouterKey(_ key: String)
    func removeOpenRouterKey()
    func setS3Settings(_ settings: S3Settings)
    func removeS3Settings()
    func getFreshToken() async throws -> String
    func triggerCredentialsRequired()
    func triggerInsufficientBalance()

    // Callback management
    func addCredentialsChangedCallback(_ callback: @escaping () -> Void) -> CallbackToken
    func addCredentialsRequiredCallback(_ callback: @escaping () -> Void) -> CallbackToken
    func removeCallback(_ token: CallbackToken)
}
