//
//  ChatStreamingAccumulator.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 15.09.2025.
//

@preconcurrency import OpenAI
import Foundation

class StreamingAccumulator: @unchecked Sendable {
    typealias ToolCallParam = ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam
    typealias ReasoningDetail = ChatResult.Choice.Message.ReasoningDetail
    private let stateQueue = DispatchQueue(label: "io.qalti.streaming.accumulator")

    private var _assistantContent: String = ""
    private var _toolCalls: [Int: (id: String?, name: String?, arguments: String, dispatched: Bool)] = [:]
    private var _didStreamAssistantMessage: Bool = false
    private var _hasBegunStreamingMessage: Bool = false
    private var _builtToolCalls: [ToolCallParam] = []
    private var _reasoningDetails: [ReasoningDetail] = []
    private var _streamError: Swift.Error? = nil

    var assistantContent: String { stateQueue.sync { _assistantContent } }
    var didStreamAssistantMessage: Bool { stateQueue.sync { _didStreamAssistantMessage } }
    var builtToolCalls: [ToolCallParam] { stateQueue.sync { _builtToolCalls } }
    var reasoningDetails: [ReasoningDetail] { stateQueue.sync { _reasoningDetails } }
    var streamError: Swift.Error? { stateQueue.sync { _streamError } }

    func setStreamError(_ error: Swift.Error?) {
        stateQueue.sync { _streamError = error }
    }

    func beginStreamingIfNeeded() -> Bool {
        stateQueue.sync {
            guard _hasBegunStreamingMessage == false else { return false }
            _hasBegunStreamingMessage = true
            _didStreamAssistantMessage = true
            return true
        }
    }

    func appendAssistantContent(_ delta: String) {
        stateQueue.sync { _assistantContent += delta }
    }

    func appendReasoningDetails(_ details: [ReasoningDetail]) {
        guard !details.isEmpty else { return }
        stateQueue.sync { _reasoningDetails.append(contentsOf: details) }
    }

    func upsertToolCall(index: Int, id: String?, name: String?, argumentsDelta: String?) {
        stateQueue.sync {
            var entry = _toolCalls[index] ?? (id: nil, name: nil, arguments: "", dispatched: false)
            if let id { entry.id = id }
            if let name { entry.name = name }
            if let argumentsDelta { entry.arguments += argumentsDelta }
            _toolCalls[index] = entry
        }
    }

    func partialToolCalls() -> [ToolCallParam] {
        stateQueue.sync {
            let sorted = _toolCalls.keys.sorted()
            var partial: [ToolCallParam] = []
            for idx in sorted {
                let e = _toolCalls[idx]!
                if let name = e.name {
                    let fn = ToolCallParam.FunctionCall(arguments: e.arguments, name: name)
                    let tc = ToolCallParam(id: e.id ?? UUID().uuidString, function: fn)
                    partial.append(tc)
                }
            }
            return partial
        }
    }

    func collectDispatchableToolCalls() -> [ToolCallParam] {
        stateQueue.sync {
            let sorted = _toolCalls.keys.sorted()
            var toDispatch: [ToolCallParam] = []
            for idx in sorted {
                guard var e = _toolCalls[idx], e.dispatched == false, let name = e.name else { continue }
                if let data = e.arguments.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) != nil {
                    e.dispatched = true
                    _toolCalls[idx] = e
                    let fn = ToolCallParam.FunctionCall(arguments: e.arguments, name: name)
                    let tc = ToolCallParam(id: e.id ?? UUID().uuidString, function: fn)
                    toDispatch.append(tc)
                }
            }
            return toDispatch
        }
    }

    func finalizeBuiltToolCalls() -> [ToolCallParam] {
        stateQueue.sync {
            let sorted = _toolCalls.keys.sorted()
            var toolCalls: [ToolCallParam] = []
            for idx in sorted {
                if let entry = _toolCalls[idx], let name = entry.name {
                    let function = ToolCallParam.FunctionCall(arguments: entry.arguments, name: name)
                    let toolCall = ToolCallParam(id: entry.id ?? UUID().uuidString, function: function)
                    toolCalls.append(toolCall)
                }
            }
            _builtToolCalls = toolCalls
            return toolCalls
        }
    }
}
