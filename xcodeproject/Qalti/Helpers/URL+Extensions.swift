//
//  URL+Extensions.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 28.11.25.
//

import Foundation

extension URL {
    func replacing(host oldAddress: String, with newAddress: String) -> URL? {
        let original = absoluteString
        guard original.contains(oldAddress) else { return nil }
        let updated = original.replacingOccurrences(of: oldAddress, with: newAddress)
        return URL(string: updated)
    }
}
