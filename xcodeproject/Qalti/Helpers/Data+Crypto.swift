//
//  Data+Crypto.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 27.11.25.
//

import Foundation
import CryptoKit

extension Data {
    
    /// Returns the SHA256 hash of the data as a hex string.
    /// Used for generating unique identifiers for Allure history and caching.
    var sha256: String {
        let digest = SHA256.hash(data: self)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
