//
//  GRPCRecordCallAdapter.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 18.12.25.
//

import GRPC


class GRPCRecordCallAdapter: RecordCall {
    private let call: GRPCAsyncBidirectionalStreamingCall<Idb_RecordRequest, Idb_RecordResponse>
    private let continuation: AsyncStream<Idb_RecordResponse>.Continuation
    private let stream: AsyncStream<Idb_RecordResponse>

    init(call: GRPCAsyncBidirectionalStreamingCall<Idb_RecordRequest, Idb_RecordResponse>) {
        self.call = call
        var tempContinuation: AsyncStream<Idb_RecordResponse>.Continuation! = nil
        self.stream = AsyncStream { cont in
            tempContinuation = cont
        }
        self.continuation = tempContinuation

        // Start a single task to forward all gRPC responses
        Task.detached {
            do {
                for try await response in call.responseStream {
                    self.continuation.yield(response)
                }
                self.continuation.finish()
            } catch {
                self.continuation.finish()
            }
        }
    }

    func send(_ message: Idb_RecordRequest) async throws {
        try await call.requestStream.send(message)
    }

    func sendEnd() async throws {
        call.requestStream.finish()
    }

    func cancel() {
        call.cancel()
    }

    func receive() async -> Idb_RecordResponse? {
        var iterator = stream.makeAsyncIterator()
        return await iterator.next()
    }
}
