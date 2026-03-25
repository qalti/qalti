//
//  SingletonStorage.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 04.03.2025.
//
import Foundation
import OpenAI
import Combine

extension Data {
    private static let base64JpegURLPrefix = "data:image/jpeg;base64,"

    func toBase64JpegURLString() -> String {
        return Self.base64JpegURLPrefix + base64EncodedString()
    }

    init?(base64JpegURLString: String) {
        if base64JpegURLString.hasPrefix(Self.base64JpegURLPrefix) {
            self.init(base64Encoded: String(base64JpegURLString.dropFirst(Self.base64JpegURLPrefix.count)))
        } else {
            return nil
        }
    }
}

@MainActor
final class RunStorage: ObservableObject {
    @Published private(set) var queue: [URL] = []
    @Published private(set) var tests: [URL: String] = [:]
    @Published private(set) var activeStatuses: [URL: RunIndicatorState] = [:]
    @Published private(set) var pendingTests: [URL] = []
    @Published private(set) var finishedStatuses: [URL: RunIndicatorState] = [:]
    private var currentTestIndex: Int?
    private var suiteTestIndexes: [URL: Int] = [:]
    private static let singleRunPlaceholderURL = URL(string: "qalti://single-test")!

    func setSingleTest(_ test: String, testURL: URL?) {
        let normalizedURL = testURL?.standardizedFileURL ?? Self.singleRunPlaceholderURL
        setTests([normalizedURL: test], queue: [normalizedURL], currentTestIndex: 0)
    }

    func setSuiteTests(_ tests: [URL: String], queue: [URL]) {
        let normalizedQueue = queue.map { $0.standardizedFileURL }
        var normalizedTests: [URL: String] = [:]
        for (url, test) in tests {
            normalizedTests[url.standardizedFileURL] = test
        }
        setTests(normalizedTests, queue: normalizedQueue, currentTestIndex: normalizedQueue.isEmpty ? nil : 0)
    }

    private func setTests(_ tests: [URL: String], queue: [URL], currentTestIndex: Int?) {
        self.currentTestIndex = currentTestIndex
        self.queue = queue
        pendingTests = queue
        suiteTestIndexes = Dictionary(uniqueKeysWithValues: queue.enumerated().map { (offset, url) in
            (url, offset)
        })
        self.tests = tests
    }

    func setCurrentTestIndex(_ index: Int?) {
        currentTestIndex = index
    }

    func updateCurrentTest(_ test: String) {
        guard let index = currentTestIndex else { return }
        updateTest(at: index, testContent: test)
    }

    func updateTest(at index: Int, testContent: String) {
        guard queue.indices.contains(index) else { return }
        let url = queue[index].standardizedFileURL
        var updatedGroups = tests
        updatedGroups[url] = testContent
        tests = updatedGroups
    }

    func testContent(for testURL: URL?) -> String? {
        guard let resolvedURL = resolvedTestURL(preferred: testURL) else { return nil }
        return tests[resolvedURL]
    }

    func currentTestURL(preferred url: URL? = nil) -> URL? {
        resolvedTestURL(preferred: url)
    }

    func popNextPendingTest() -> URL? {
        guard !pendingTests.isEmpty else { return nil }
        return pendingTests.removeFirst()
    }

    func suiteIndex(for url: URL) -> Int? {
        suiteTestIndexes[url.standardizedFileURL]
    }

    func clear() {
        currentTestIndex = nil
        queue = []
        tests = [:]
        pendingTests = []
        suiteTestIndexes = [:]
        clearStatuses()
    }

    func setActiveStatus(_ state: RunIndicatorState, for url: URL) {
        setActiveStatus(state, for: [url])
    }

    func setActiveStatus(_ state: RunIndicatorState, for urls: [URL]) {
        var statuses = activeStatuses
        var finished = finishedStatuses
        for url in urls {
            let normalized = url.standardizedFileURL
            switch state {
            case .queued, .running:
                statuses[normalized] = state
                finished.removeValue(forKey: normalized)
            case .success, .failed, .cancelled:
                finished[normalized] = state
                statuses.removeValue(forKey: normalized)
            }
        }
        activeStatuses = statuses
        finishedStatuses = finished
    }

    func clearStatus(for url: URL) {
        var statuses = activeStatuses
        statuses.removeValue(forKey: url.standardizedFileURL)
        activeStatuses = statuses
        var finished = finishedStatuses
        finished.removeValue(forKey: url.standardizedFileURL)
        finishedStatuses = finished
    }

    func clearStatuses() {
        activeStatuses = [:]
        finishedStatuses = [:]
    }

    func status(for url: URL) -> RunIndicatorState? {
        activeStatuses[url.standardizedFileURL]
    }

    private func resolvedTestURL(preferred testURL: URL?) -> URL? {
        if let normalized = testURL?.standardizedFileURL {
            return normalized
        }

        if let index = currentTestIndex, queue.indices.contains(index) {
            return queue[index].standardizedFileURL
        }

        if let first = queue.first {
            return first.standardizedFileURL
        }

        return tests.keys.first
    }
}

// MARK: - Custom Content Parts for Enhanced Image Storage

/// Represents the type of image data to retrieve
enum ImageDataType {
    case url      // URL only for LLM consumption
    case base64   // Base64 data for UI display and logging
}

/// Enhanced content part that stores both URL and base64 image data
enum EnhancedContentPart {
    case text(String)
    case imageWithData(url: String, base64JpegURLString: String)

    /// Convert to standard OpenAI content part based on desired image type
    func toContentPart(imageType: ImageDataType) -> ChatQuery.ChatCompletionMessageParam.UserMessageParam.Content.ContentPart {
        switch self {
        case .text(let text):
            return .text(.init(text: text))
        case .imageWithData(let url, let base64JpegURLString):
            switch imageType {
            case .url:
                return .image(.init(imageUrl: .init(url: url, detail: .auto)))
            case .base64:
                return .image(.init(imageUrl: .init(url: base64JpegURLString, detail: .auto)))
            }
        }
    }
}

/// Enhanced message that can store both URL and base64 data with timestamps
enum EnhancedMessage {
    typealias ReasoningDetail = ChatResult.Choice.Message.ReasoningDetail
    case system(ChatQuery.ChatCompletionMessageParam.SystemMessageParam, timestamp: Date)
    case user(ChatQuery.ChatCompletionMessageParam.UserMessageParam, enhancedParts: [EnhancedContentPart]?, timestamp: Date)
    case assistant(ChatQuery.ChatCompletionMessageParam.AssistantMessageParam, timestamp: Date)
    case tool(ChatQuery.ChatCompletionMessageParam.ToolMessageParam, timestamp: Date)
    case developer(ChatQuery.ChatCompletionMessageParam.DeveloperMessageParam, timestamp: Date)

    /// Convert to standard ChatQuery message based on desired image type
    func toChatMessage(imageType: ImageDataType) -> ChatQuery.ChatCompletionMessageParam {
        switch self {
        case .system(let param, _):
            return .system(param)
        case .user(let param, let enhancedParts, _):
            if let enhancedParts = enhancedParts {
                // Use enhanced parts with desired image type
                let contentParts = enhancedParts.compactMap { part -> ChatQuery.ChatCompletionMessageParam.UserMessageParam.Content.ContentPart? in
                    switch part {
                    case .text(let text):
                        if text.trimmingCharacters(in: .whitespacesAndNewlines).count == 0 {
                            return nil
                        } else {
                            return part.toContentPart(imageType: imageType)
                        }
                    default:
                        return part.toContentPart(imageType: imageType)
                    }
                }
                let updatedParam = ChatQuery.ChatCompletionMessageParam.UserMessageParam(
                    content: .contentParts(contentParts),
                    name: param.name
                )
                return .user(updatedParam)
            } else {
                // Use original param
                return .user(param)
            }
        case .assistant(let param, _):
            return .assistant(param)
        case .tool(let param, _):
            return .tool(param)
        case .developer(let param, _):
            return .developer(param)
        }
    }

    /// Check if this is a standard message (can be converted directly)
    var isStandardMessage: Bool {
        switch self {
        case .user(_, let enhancedParts, _):
            return enhancedParts == nil
        default:
            return true
        }
    }

    /// Get the timestamp of this message
    var timestamp: Date {
        switch self {
        case .system(_, let timestamp):
            return timestamp
        case .user(_, _, let timestamp):
            return timestamp
        case .assistant(_, let timestamp):
            return timestamp
        case .tool(_, let timestamp):
            return timestamp
        case .developer(_, let timestamp):
            return timestamp
        }
    }
}

// MARK: - Refactored RunHistory (No more array callbacks)

/// Per-run record of the agent conversation and execution state.
///
/// The same instance feeds three consumers:
/// - The agent loop (`IOSAgent`) treats it as the canonical chat history.
/// - UI components (`ChatReplayView`, `AssistantView`) observe it for replay.
/// - Report/export writers snapshot it once the run completes.
///
/// RunHistory only contains messages produced during the current execution.
/// Saved reports instantiate their own RunHistory when viewed later.
final class RunHistory {

    private let mutationQueueSpecificKey = DispatchSpecificKey<Void>()
    private lazy var mutationQueue: DispatchQueue = {
        let queue = DispatchQueue(label: "io.qalti.runHistory.mutation")
        queue.setSpecific(key: mutationQueueSpecificKey, value: ())
        return queue
    }()

    // Private storage
    private var enhancedChatHistoryStorage: [EnhancedMessage] = []
    private var runInProgressStorage: Bool = false
    private var currentRunStartTimeStorage: Date? = nil

    /// Index of the assistant message currently being streamed (if any)
    private var streamingAssistantMessageIndex: Int? = nil

    // Observers
    private var observers: [UUID: () -> Void] = [:]
    private var runStateObservers: [UUID: (Bool) -> Void] = [:]

    @inline(__always)
    @discardableResult
    private func withHistoryLock<T>(_ block: () -> T) -> T {
        if DispatchQueue.getSpecific(key: mutationQueueSpecificKey) != nil {
            return block()
        } else {
            return mutationQueue.sync(execute: block)
        }
    }

    // MARK: - Observer Registration API (Thread-Safe)

    // Public Read-Only Accessors (Thread-Safe via Lock)
    var enhancedChatHistory: [EnhancedMessage] {
        withHistoryLock { enhancedChatHistoryStorage }
    }

    func registerObserver(_ block: @escaping () -> Void) -> UUID {
        let id = UUID()
        withHistoryLock { observers[id] = block }
        return id
    }
    func removeObserver(id: UUID) {
        withHistoryLock { observers.removeValue(forKey: id) }
    }

    func registerRunStateObserver(_ block: @escaping (Bool) -> Void) -> UUID {
        let id = UUID()
        withHistoryLock { runStateObservers[id] = block }
        return id
    }
    func removeRunStateObserver(id: UUID) {
        withHistoryLock { runStateObservers.removeValue(forKey: id) }
    }

    // MARK: - State Management (Thread-Safe Setters)

    func setRunInProgress(_ inProgress: Bool) {
        var callbacksToNotify: [(Bool) -> Void] = []

        withHistoryLock {
            if runInProgressStorage != inProgress {
                runInProgressStorage = inProgress
                currentRunStartTimeStorage = inProgress ? Date() : nil
                callbacksToNotify = Array(runStateObservers.values)
            }
        }

        for callback in callbacksToNotify {
            callback(inProgress)
        }
    }

    /// Returns the start time of the currently executing test run
    func getCurrentRunStartTime() -> Date? {
        withHistoryLock {
            currentRunStartTimeStorage
        }
    }

    /// Returns true when a test (single or suite) is currently executing
    func isRunInProgress() -> Bool {
        withHistoryLock {
            runInProgressStorage
        }
    }

    /// Checks if the history contains any messages that would be visible in the UI.
    func hasDisplayableContent() -> Bool {
        return withHistoryLock {
            enhancedChatHistoryStorage.contains { message in
                if case .system = message { return false }
                return true
            }
        }
    }

    // MARK: - History Accessors

    /// Get chat history converted to standard format with specified image type
    /// - Parameter imageType: .url for LLM consumption, .base64 for UI display/logging
    /// - Returns: Array of standard ChatQuery messages
    func getHistory(imageType: ImageDataType = .url) -> [ChatQuery.ChatCompletionMessageParam] {
        return withHistoryLock {
            enhancedChatHistoryStorage.map { $0.toChatMessage(imageType: imageType) }
        }
    }

    func setHistory(_ messages: [ChatQuery.ChatCompletionMessageParam]) {
        let codableMessages = messages.map { CodableChatMessage(message: $0, timestamp: Date(), parsedComments: nil) }
        loadTranscript(codableMessages)
    }

    /// Get the count of messages in the chat history
    var count: Int {
        return withHistoryLock { enhancedChatHistoryStorage.count }
    }

    func clearHistory() {
        var callbacksToNotify: [() -> Void] = []
        withHistoryLock {
            enhancedChatHistoryStorage = []
            streamingAssistantMessageIndex = nil
            callbacksToNotify = Array(observers.values)
        }
        for callback in callbacksToNotify { callback() }
    }

    func append(_ message: ChatQuery.ChatCompletionMessageParam) {
        var callbacksToNotify: [() -> Void] = []
        withHistoryLock {
            let enhancedMessage: EnhancedMessage
            let timestamp = Date()
            switch message {
            case .system(let param):
                enhancedMessage = .system(param, timestamp: timestamp)
            case .user(let param):
                enhancedMessage = .user(param, enhancedParts: nil, timestamp: timestamp)
            case .assistant(let param):
                enhancedMessage = .assistant(param, timestamp: timestamp)
            case .tool(let param):
                enhancedMessage = .tool(param, timestamp: timestamp)
            case .developer(let param):
                enhancedMessage = .developer(param, timestamp: timestamp)
            }
            enhancedChatHistoryStorage.append(enhancedMessage)
            callbacksToNotify = Array(observers.values)
        }
        for callback in callbacksToNotify { callback() }
    }

    /// Append enhanced message with both URL and base64 data
    func appendEnhanced(_ enhancedMessage: EnhancedMessage) {
        var callbacksToNotify: [() -> Void] = []
        withHistoryLock {
            enhancedChatHistoryStorage.append(enhancedMessage)
            callbacksToNotify = Array(observers.values)
        }
        for callback in callbacksToNotify { callback() }
    }

    /// Create and append user message with screenshot data
    func appendUserWithScreenshot(textContent: String, imageURL: String, imageData: Data, useGeminiFix: Bool) {
        var callbacksToNotify: [() -> Void] = []
        withHistoryLock {
            if useGeminiFix {
                let enhancedParts: [EnhancedContentPart] = [
                    .imageWithData(url: imageURL, base64JpegURLString: imageData.toBase64JpegURLString())
                ]

                let userParam = ChatQuery.ChatCompletionMessageParam.UserMessageParam(content: .string(""), name: nil)

                let enhancedMessage = EnhancedMessage.user(userParam, enhancedParts: enhancedParts, timestamp: Date())
                let textMessage = EnhancedMessage.user(.init(content: .string(textContent)), enhancedParts: nil, timestamp: Date())
                enhancedChatHistoryStorage.append(enhancedMessage)
                enhancedChatHistoryStorage.append(textMessage)
                callbacksToNotify = Array(observers.values)
            } else {
                let enhancedParts: [EnhancedContentPart] = [
                    .text(textContent),
                    .imageWithData(url: imageURL, base64JpegURLString: imageData.toBase64JpegURLString())
                ]

                let userParam = ChatQuery.ChatCompletionMessageParam.UserMessageParam(
                    content: .string(textContent),
                    name: nil
                )

                let enhancedMessage = EnhancedMessage.user(userParam, enhancedParts: enhancedParts, timestamp: Date())
                enhancedChatHistoryStorage.append(enhancedMessage)
                callbacksToNotify = Array(observers.values)
            }
        }
        for callback in callbacksToNotify { callback() }
    }

    func loadTranscript(_ messages: [CodableChatMessage]) {
        var callbacksToNotify: [() -> Void] = []
        withHistoryLock {
            enhancedChatHistoryStorage = messages.map { codableMessage in
                let message = codableMessage.message
                let timestamp = codableMessage.timestamp

                switch message {
                case .system(let param):
                    return .system(param, timestamp: timestamp)
                case .user(let param):
                    return .user(param, enhancedParts: nil, timestamp: timestamp)
                case .assistant(let param):
                    return .assistant(param, timestamp: timestamp)
                case .tool(let param):
                    return .tool(param, timestamp: timestamp)
                case .developer(let param):
                    return .developer(param, timestamp: timestamp)
                }
            }
            streamingAssistantMessageIndex = nil
            callbacksToNotify = Array(observers.values)
        }
        for callback in callbacksToNotify { callback() }
    }

    // MARK: - Assistant Streaming Support

    /// Begin an assistant streaming message by appending an empty assistant entry.
    /// Returns the index of the newly created streaming assistant message.
    @discardableResult
    func beginAssistantStreaming() -> Int {
        var callbacksToNotify: [() -> Void] = []
        let index = withHistoryLock {
            let assistantParam = ChatQuery.ChatCompletionMessageParam.AssistantMessageParam(content: .textContent(""), audio: nil, name: "assistant", toolCalls: nil, reasoningDetails: nil)
            let enhancedMessage: EnhancedMessage = .assistant(assistantParam, timestamp: Date())
            enhancedChatHistoryStorage.append(enhancedMessage)
            let idx = enhancedChatHistoryStorage.count - 1
            streamingAssistantMessageIndex = idx
            callbacksToNotify = Array(observers.values)
            return idx
        }
        for callback in callbacksToNotify { callback() }
        return index
    }

    func appendAssistantStreamingContent(_ delta: String) {
        var callbacksToNotify: [() -> Void] = []
        withHistoryLock {
            guard let idx = streamingAssistantMessageIndex,
                  idx >= 0,
                  idx < enhancedChatHistoryStorage.count
            else { return }

            if case .assistant(let param, let timestamp) = enhancedChatHistoryStorage[idx] {
                var accumulated = ""
                if let content = param.content {
                    switch content {
                    case .textContent(let text):
                        accumulated = text
                    default:
                        accumulated = ""
                    }
                }
                let updatedParam = ChatQuery.ChatCompletionMessageParam.AssistantMessageParam(
                    content: .textContent(accumulated + delta),
                    audio: param.audio,
                    name: param.name,
                    toolCalls: param.toolCalls,
                    reasoningDetails: param.reasoningDetails
                )
                enhancedChatHistoryStorage[idx] = .assistant(updatedParam, timestamp: timestamp)
                callbacksToNotify = Array(observers.values)
            }
        }
        for callback in callbacksToNotify { callback() }
    }

    func finalizeAssistantStreaming(
        toolCalls: [ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam]?,
        reasoningDetails: [EnhancedMessage.ReasoningDetail]?
    ) {
        var callbacksToNotify: [() -> Void] = []
        withHistoryLock {
            guard let idx = streamingAssistantMessageIndex,
                  idx >= 0,
                  idx < enhancedChatHistoryStorage.count
            else {
                streamingAssistantMessageIndex = nil
                return
            }
            if case .assistant(let param, let timestamp) = enhancedChatHistoryStorage[idx] {
                let updatedParam = ChatQuery.ChatCompletionMessageParam.AssistantMessageParam(
                    content: param.content,
                    audio: param.audio,
                    name: param.name,
                    toolCalls: (toolCalls?.count ?? 0) > 0 ? toolCalls : nil,
                    reasoningDetails: reasoningDetails ?? param.reasoningDetails
                )
                enhancedChatHistoryStorage[idx] = .assistant(updatedParam, timestamp: timestamp)
                callbacksToNotify = Array(observers.values)
            }
            streamingAssistantMessageIndex = nil
        }
        for callback in callbacksToNotify { callback() }
    }

    func updateAssistantStreamingToolCalls(_ toolCalls: [ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam]) {
        var callbacksToNotify: [() -> Void] = []
        withHistoryLock {
            guard let idx = streamingAssistantMessageIndex,
                  idx >= 0,
                  idx < enhancedChatHistoryStorage.count
            else { return }
            if case .assistant(let param, let timestamp) = enhancedChatHistoryStorage[idx] {
                let updatedParam = ChatQuery.ChatCompletionMessageParam.AssistantMessageParam(
                    content: param.content,
                    audio: param.audio,
                    name: param.name,
                    toolCalls: toolCalls,
                    reasoningDetails: param.reasoningDetails
                )
                enhancedChatHistoryStorage[idx] = .assistant(updatedParam, timestamp: timestamp)
                callbacksToNotify = Array(observers.values)
            }
        }
        for callback in callbacksToNotify { callback() }
    }

}

/// Helper that manages RunHistory observer lifetimes.
final class RunHistoryObservation {
    private weak var history: RunHistory?
    private var historyTokens: [UUID] = []
    private var runStateTokens: [UUID] = []

    init(history: RunHistory) {
        self.history = history
    }

    func observeHistory(_ block: @escaping () -> Void) {
        guard let history else { return }
        let token = history.registerObserver(block)
        historyTokens.append(token)
    }

    func observeRunState(_ block: @escaping (Bool) -> Void) {
        guard let history else { return }
        let token = history.registerRunStateObserver(block)
        runStateTokens.append(token)
    }

    func cancel() {
        guard let history else {
            historyTokens.removeAll()
            runStateTokens.removeAll()
            return
        }

        for token in historyTokens {
            history.removeObserver(id: token)
        }
        for token in runStateTokens {
            history.removeRunStateObserver(id: token)
        }
        historyTokens.removeAll()
        runStateTokens.removeAll()
    }

    deinit {
        cancel()
    }
}
