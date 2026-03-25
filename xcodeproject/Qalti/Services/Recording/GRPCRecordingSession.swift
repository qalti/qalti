//
//  GRPCRecordingSession.swift
//  Qalti
//

import Foundation
import Logging
import GRPC


final class GRPCRecordingSession: GRPCRecordingSessionProtocol, Loggable {

    private let idbManager: IdbManaging
    private let fileManager: FileSystemManaging
    private var recordCall: RecordCall?
    private var streamingTask: Task<Void, Never>?

    let outputURL: URL
    private var fileHandle: FileHandle?

    enum RecordingError: Error {
        case fileHandleCreationFailed
        case streamInitializationFailed(Error)
    }

    init(outputURL: URL, idbManager: IdbManaging, fileManager: FileSystemManaging) {
        self.idbManager = idbManager
        self.fileManager = fileManager
        self.outputURL = outputURL
    }

    deinit {
        if streamingTask != nil {
            logger.warning("GRPCRecordingSession deallocated while streaming task is active.")
        }
        try? fileHandle?.close()
        streamingTask?.cancel()
    }

    func start(udid: String) throws {
        try fileManager.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil)

        if fileManager.fileExists(atPath: outputURL.path, isDirectory: nil) {
            try fileManager.removeItem(at: outputURL)
        }

        guard fileManager.createFile(atPath: outputURL.path, contents: nil, attributes: nil) else {
            throw RecordingError.fileHandleCreationFailed
        }

        fileHandle = try FileHandle(forWritingTo: outputURL)

        do {
            let recordCall = try idbManager.record(udid: udid)
            self.recordCall = recordCall

            streamingTask = Task { [weak self] in
                guard let self = self else { return }
                let startRequest = Idb_RecordRequest.with { $0.start = .with { $0.filePath = self.outputURL.path } }

                do {
                    try await recordCall.send(startRequest)

                    while let response = await recordCall.receive() {
                        if case .payload(let payload) = response.output,
                           case .data(let data) = payload.source,
                           !data.isEmpty {
                            try fileHandle?.write(contentsOf: data)
                        }
                    }

                } catch {
                    if !Task.isCancelled {
                        logger.error("Record stream failed: \(error)")
                    }
                }
            }

        } catch {
            throw RecordingError.streamInitializationFailed(error)
        }
    }

    func stop() async {
        guard let call = recordCall,
              let task = streamingTask else { return }

        let stopRequest = Idb_RecordRequest.with { $0.stop = .init() }

        do {
            try await call.send(stopRequest)
            try await call.sendEnd()
        } catch {
            logger.error("Failed to send stop request: \(error)")
        }

        await task.value

        do {
            try fileHandle?.synchronize()
            try fileHandle?.close()
            logger.info("Video file saved to: \(outputURL.path)")

        } catch {
            logger.error("Failed to finalize video file: \(error)")
        }

        fileHandle = nil
        streamingTask = nil
        recordCall = nil
    }
}
