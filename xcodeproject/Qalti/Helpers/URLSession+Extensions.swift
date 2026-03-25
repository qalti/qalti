//
//  URLSession+Extensions.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 28.11.25.
//

import Foundation

extension URLSession {
    func uncachedTask(
        with url: URL,
        completion: @escaping (Data?, URLResponse?, (any Error)?) -> Void
    ) -> URLSessionDataTask {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        return dataTask(with: request, completionHandler: completion)
    }

    func uncachedTask(
        with request: URLRequest,
        completion: @escaping (Data?, URLResponse?, (any Error)?) -> Void
    ) -> URLSessionDataTask {
        var request = request
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return dataTask(with: request, completionHandler: completion)
    }
}
