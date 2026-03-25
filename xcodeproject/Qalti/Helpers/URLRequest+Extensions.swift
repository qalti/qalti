//
//  URLRequest+Extensions.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 28.11.25.
//

import Foundation

extension URLRequest {
    func replacing(host oldAddress: String, with newAddress: String) -> URLRequest? {
        guard let updatedURL = url?.replacing(host: oldAddress, with: newAddress) else {
            return nil
        }
        var newRequest = self
        newRequest.url = updatedURL
        return newRequest
    }
}
