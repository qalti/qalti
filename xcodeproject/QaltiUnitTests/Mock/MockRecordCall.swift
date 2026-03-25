//
//  MockRecordCall.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 18.12.25.
//

import Foundation
@testable import Qalti


class MockRecordCall: RecordCall {
    var sentMessages: [Idb_RecordRequest] = []
    var isEnded = false
    var isCancelled = false

    func send(_ message: Idb_RecordRequest) async throws {
        sentMessages.append(message)
    }

    func sendEnd() async throws {
        isEnded = true
    }

    func cancel() {
        isCancelled = true
    }

    func receive() async -> Idb_RecordResponse? {
        return nil
    }
}
