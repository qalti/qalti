//
//  FakeRecordCall.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 23.12.25.
//

class FakeRecordCall: RecordCall {
    func send(_ message: Idb_RecordRequest) async throws {

    }
    
    func sendEnd() async throws {

    }
    
    func cancel() {

    }
    
    func receive() async -> Idb_RecordResponse? {
        return nil
    }
}
