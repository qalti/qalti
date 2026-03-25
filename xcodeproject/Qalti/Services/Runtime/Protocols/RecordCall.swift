//
//  RecordCall.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 18.12.25.
//

import Foundation

protocol RecordCall {
    func send(_ message: Idb_RecordRequest) async throws
    func sendEnd() async throws
    func cancel()
    func receive() async -> Idb_RecordResponse?
}
