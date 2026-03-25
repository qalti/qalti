import SwiftUI
import OpenAI
import Foundation
import MarkdownUI
import Logging

// MARK: - Mapped Message Types

enum MappedMessage {
    case single(ChatQuery.ChatCompletionMessageParam, timestamp: Date)
    case assistantStep( AssistantStepInfo)
    case partialAssistantStep(
        userMessage: ChatQuery.ChatCompletionMessageParam?,
        assistantMessage: ChatQuery.ChatCompletionMessageParam? = nil,
        originalUserMessage: EnhancedMessage?,
        userTimestamp: Date?,
        assistantTimestamp: Date?
    )
    case testResult(TestResult, duration: TimeInterval?)
}

struct AssistantStepInfo {
    let userMessage: ChatQuery.ChatCompletionMessageParam?
    let assistantMessage: ChatQuery.ChatCompletionMessageParam
    let toolResponse: ChatQuery.ChatCompletionMessageParam?

    let originalUserMessage: EnhancedMessage?

    let userTimestamp: Date?
    let assistantTimestamp: Date
    let toolTimestamp: Date?

    var executionDuration: TimeInterval? {
        guard let toolTimestamp = toolTimestamp else { return nil }
        let startTime = userTimestamp ?? assistantTimestamp
        let duration = toolTimestamp.timeIntervalSince(startTime)
        return duration > 0 ? duration : nil
    }
}

// MARK: - Message Mapping Logic

class MessageMapper {
    let errorCapturer: ErrorCapturing

    init(errorCapturer: ErrorCapturing) {
        self.errorCapturer = errorCapturer
    }

    func mapMessages(_ messages: [EnhancedMessage]) -> [MappedMessage] {
        guard !messages.isEmpty else { return [] }

        var mappedMessages: [MappedMessage] = []
        var testResult: TestResult? = nil
        var processedMessages = messages

        // Parse the last message for test results before processing
        if let lastMessage = messages.last,
           case .assistant(let assistantParam, _) = lastMessage,
           let content = assistantParam.content,
           case .textContent(let text) = content
        {
            let contentParser = ContentParser(errorCapturer: errorCapturer)
            let parsedContent = contentParser.parseContent(text)
            if let extractedTestResult = parsedContent.testResult {
                testResult = extractedTestResult

                // Replace the last message's content to remove the JSON block from display
                if case .assistant(let originalParam, let timestamp) = lastMessage {
                    let updatedParam = ChatQuery.ChatCompletionMessageParam.AssistantMessageParam(
                        content: .textContent(parsedContent.mainContent),
                        audio: originalParam.audio,
                        name: originalParam.name,
                        toolCalls: originalParam.toolCalls,
                        reasoningDetails: originalParam.reasoningDetails
                    )
                    processedMessages[processedMessages.count - 1] = .assistant(updatedParam, timestamp: timestamp)
                }
            }
        }

        // Walk through messages and build logical steps
        var index = 0
        while index < processedMessages.count {

            // Pattern A* user -> user -> assistant -> tool (Gemini fix)
            if index + 3 < processedMessages.count,
               case .user(_, let enhancedPart, let userTimestamp) = processedMessages[index],
               case .user(let userText, let noEnhancedPart, _) = processedMessages[index + 1],
               case .assistant(_, let assistantTimestamp) = processedMessages[index + 2],
               case .tool(_, let toolTimestamp) = processedMessages[index + 3],
               enhancedPart != nil,
               noEnhancedPart == nil
            {
                let assistantMsg = processedMessages[index + 2].toChatMessage(imageType: .url)
                let toolMsg = processedMessages[index + 3].toChatMessage(imageType: .url)

                let mergedUserMessage = EnhancedMessage.user(userText, enhancedParts: enhancedPart, timestamp: userTimestamp)

                let stepInfo = AssistantStepInfo(
                    userMessage: mergedUserMessage.toChatMessage(imageType: .url),
                    assistantMessage: assistantMsg,
                    toolResponse: toolMsg,
                    originalUserMessage: mergedUserMessage,
                    userTimestamp: userTimestamp,
                    assistantTimestamp: assistantTimestamp,
                    toolTimestamp: toolTimestamp
                )
                mappedMessages.append(.assistantStep(stepInfo))
                index += 4
                continue
            }

            // Pattern A: user -> assistant -> tool (Complete Step)
            if index + 2 < processedMessages.count,
               case .user(_, _, let userTimestamp) = processedMessages[index],
               case .assistant(_, let assistantTimestamp) = processedMessages[index + 1],
               case .tool(_, let toolTimestamp) = processedMessages[index + 2]
            {
                let originalUserMessage = processedMessages[index]

                let userMsg = originalUserMessage.toChatMessage(imageType: .url)
                let assistantMsg = processedMessages[index + 1].toChatMessage(imageType: .url)
                let toolMsg = processedMessages[index + 2].toChatMessage(imageType: .url)

                let stepInfo = AssistantStepInfo(
                    userMessage: userMsg,
                    assistantMessage: assistantMsg,
                    toolResponse: toolMsg,
                    originalUserMessage: originalUserMessage,
                    userTimestamp: userTimestamp,
                    assistantTimestamp: assistantTimestamp,
                    toolTimestamp: toolTimestamp
                )
                mappedMessages.append(.assistantStep(stepInfo))
                index += 3
                continue
            }

            // Pattern B*: user -> user -> assistant (Gemini Partial Step, e.g., streaming in progress)
            if index + 2 < processedMessages.count,
               case .user(_, let enhancedPart, let userTimestamp) = processedMessages[index],
               case .user(let userText, let noEnhancedPart, _) = processedMessages[index + 1],
               case .assistant(_, let assistantTimestamp) = processedMessages[index + 2],
               enhancedPart != nil,
               noEnhancedPart == nil
            {
                let mergedUserMessage = EnhancedMessage.user(userText, enhancedParts: enhancedPart, timestamp: userTimestamp)
                let assistantMsg = processedMessages[index + 2].toChatMessage(imageType: .url)

                mappedMessages.append(.partialAssistantStep(
                    userMessage: mergedUserMessage.toChatMessage(imageType: .url),
                    assistantMessage: assistantMsg,
                    originalUserMessage: mergedUserMessage,
                    userTimestamp: userTimestamp,
                    assistantTimestamp: assistantTimestamp
                ))
                index += 3
                continue
            }

            // Pattern B: user -> assistant (Partial Step, e.g., streaming in progress)
            if index + 1 < processedMessages.count,
               case .user(_, _, let userTimestamp) = processedMessages[index],
               case .assistant(_, let assistantTimestamp) = processedMessages[index + 1]
            {
                let originalUserMessage = processedMessages[index]
                let userMsg = originalUserMessage.toChatMessage(imageType: .url)
                let assistantMsg = processedMessages[index + 1].toChatMessage(imageType: .url)

                mappedMessages.append(.partialAssistantStep(
                    userMessage: userMsg,
                    assistantMessage: assistantMsg,
                    originalUserMessage: originalUserMessage,
                    userTimestamp: userTimestamp,
                    assistantTimestamp: assistantTimestamp
                ))
                index += 2
                continue
            }

            // Pattern C: assistant -> tool (Step without a preceding user screenshot)
            if index + 1 < processedMessages.count,
               case .assistant(_, let assistantTimestamp) = processedMessages[index],
               case .tool(_, let toolTimestamp) = processedMessages[index + 1]
            {
                let assistantMsg = processedMessages[index].toChatMessage(imageType: .base64)
                let toolMsg = processedMessages[index + 1].toChatMessage(imageType: .base64)

                let stepInfo = AssistantStepInfo(
                    userMessage: nil,
                    assistantMessage: assistantMsg,
                    toolResponse: toolMsg,
                    originalUserMessage: nil,
                    userTimestamp: nil, // No user message in this pattern
                    assistantTimestamp: assistantTimestamp,
                    toolTimestamp: toolTimestamp
                )
                mappedMessages.append(.assistantStep(stepInfo))
                index += 2
                continue
            }

            // Pattern D*: user -> user (Gemini Fix user message)
            if index + 1 < processedMessages.count,
               case .user(_, let enhancedPart, let userTimestamp) = processedMessages[index],
               case .user(let userText, let noEnhancedPart, _) = processedMessages[index + 1],
               enhancedPart != nil,
               noEnhancedPart == nil
            {
                let mergedUserMessage = EnhancedMessage.user(userText, enhancedParts: enhancedPart, timestamp: userTimestamp)

                mappedMessages.append(.single(mergedUserMessage.toChatMessage(imageType: .base64), timestamp: userTimestamp))
                index += 2
                continue
            }


            // Fallback: Treat as a single, standalone message.
            let currentMessage = processedMessages[index]
            let currentMsg = currentMessage.toChatMessage(imageType: .base64)
            mappedMessages.append(.single(currentMsg, timestamp: currentMessage.timestamp))
            index += 1
        }

        // Add test result as separate message type at the end if it exists
        if let testResult = testResult {
            var totalDuration: TimeInterval? = nil

            if let firstMessage = processedMessages.first, let lastMessage = processedMessages.last {
                let calculatedDuration = lastMessage.timestamp.timeIntervalSince(firstMessage.timestamp)

                if calculatedDuration > 0 {
                    totalDuration = calculatedDuration
                }
            }
            mappedMessages.append(.testResult(testResult, duration: totalDuration))
        }

        return mappedMessages
    }
}

enum MessageType {
    case system, user, assistant, tool, developer
}

// MARK: - Preference Keys
struct BottomOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let next = nextValue() {
            value = next
        }
    }
}

struct ChatReplayView: View {
    private let logger = Logger(label: "ChatReplayView")
    private let runHistory: RunHistory
    private let errorCapturer: ErrorCapturing

    @ObservedObject private var replayState: ReplayState
    @ObservedObject var viewModel: ChatReplayViewModel

    let fileURL: URL?
    let testRun: TestRunData?

    @EnvironmentObject private var runStorage: RunStorage

    @StateObject private var scrollMonitor = ScrollMonitor()

    @State private var mappedMessages: [MappedMessage] = []
    @State private var displayedMessages: [MappedMessage] = []

    @State private var shouldShowControls = false
    @State private var showControls = false
    @State private var isTestRunning: Bool
    @State private var currentRunStartTime: Date?

    // Scroll State
    @State private var isProgrammaticallyScrolling = false
    @State private var observerHandles: [RunHistoryObservation] = []

    // Replay controls
    @State private var isReplaying = false
    @State private var replayProgress: Double = 0
    @State private var replayTimer: Timer?
    @State private var userMovedSlider = false
    @State private var updateTicker: Int = 0

    private let scrollSpace = "scroll"

    var canReplay: Bool {
        return !mappedMessages.isEmpty
    }

    init(
        fileURL: URL? = nil,
        testRun: TestRunData? = nil,
        viewModel: ChatReplayViewModel,
        runHistory: RunHistory,
        replayState: ReplayState,
        errorCapturer: ErrorCapturing
    ) {
        self.fileURL = fileURL
        self.testRun = testRun
        self.viewModel = viewModel
        self.runHistory = runHistory
        self.errorCapturer = errorCapturer
        self._replayState = ObservedObject(initialValue: replayState)
        _isTestRunning = State(initialValue: runHistory.isRunInProgress())
        _currentRunStartTime = State(initialValue: runHistory.getCurrentRunStartTime())
    }

    private static let hiddenMessagesCount = 1
    private var resolvedFileURL: URL? { fileURL ?? runStorage.currentTestURL() }
    private var isEffectivelyRunning: Bool {
        if let url = resolvedFileURL, runStorage.finishedStatuses[url.standardizedFileURL] != nil { return false }
        return isTestRunning
    }
    private func effectiveMessageCount() -> Int {
        let filteredMessages = getFilteredEnhancedMessages(from: runHistory.enhancedChatHistory)
        return calculateLogicalStepCount(from: filteredMessages)
    }
    private func calculateLogicalStepCount(from messages: [EnhancedMessage]) -> Int {
        return iterateLogicalSteps(in: messages, maxSteps: nil).stepCount
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            fileNavHeader
                .zIndex(1)

            GeometryReader { geometry in
                ZStack {
                    ScrollViewReader { proxy in
                        chatContent(proxy: proxy, geometry: geometry)
                    }

                    controlsOverlay
                }
                .navigationTitle("Chat Replay")
                .coordinateSpace(name: scrollSpace)
                .onDisappear {
                    cleanup()
                }
            }
            .zIndex(0)
        }
    }

    // MARK: - Subviews

    private var fileNavHeader: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text(displayFileName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let fileTag {
                    Text(fileTag)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.15))
                        )
                }
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(Color.secondarySystemBackground.opacity(0.95))
    }

    private var displayFileName: String {
        guard let fileURL else { return "Run" }

        let lastPathComponent = fileURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !lastPathComponent.isEmpty {
            return lastPathComponent
        }

        if let host = fileURL.host, !host.isEmpty {
            return host
        }

        return fileURL.absoluteString
    }

    private var fileTag: String? {
        guard let fileURL else { return nil }
        let ext = fileURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ext.isEmpty else { return nil }
        return ext.uppercased()
    }

    private func chatContent(proxy: ScrollViewProxy, geometry: GeometryProxy) -> some View {
        let horizontalPadding: CGFloat = 16
        let contentWidth = geometry.size.width - horizontalPadding * 2

        return ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(displayedMessages.indices, id: \.self) { index in
                    MappedMessageView(
                        mappedMessage: displayedMessages[index],
                        isLast: index == displayedMessages.indices.last,
                        isTestRunning: isEffectivelyRunning,
                        currentRunStartTime: currentRunStartTime,
                        availableWidth: contentWidth
                    )
                    .id(index)
                }

                // Invisible anchor at the bottom
                Color.clear
                    .frame(height: 62)
                    .id("bottom")
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: BottomOffsetPreferenceKey.self,
                                value: geo.frame(in: .named(scrollSpace)).maxY
                            )
                        }
                    )
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical)
            .legacy_scrollTargetLayout()
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: ContentHeightPreferenceKey.self, value: geo.size.height)
                }
            )
        }
        // MARK: - Content Growth Logic
        .onPreferenceChange(ContentHeightPreferenceKey.self) { newHeight in
            let oldHeight = viewModel.contentHeight
            viewModel.contentHeight = newHeight

            // If content grows and we are locked, scroll to bottom
            if viewModel.isUserScrolledToBottom && newHeight > oldHeight {
                scrollToBottomWithRetries(proxy, source: "Content Height Changed")
            }
        }
        // MARK: - Bottom Hit Detection
        .onPreferenceChange(BottomOffsetPreferenceKey.self) { bottomOffsetValue in
            guard let bottomOffset = bottomOffsetValue else { return }

            // Calculate if we are visually at the bottom
            let viewportHeight = geometry.size.height
            let distanceFromBottom = bottomOffset - viewportHeight
            let isAtBottom = distanceFromBottom <= 50

            // RE-LOCK LOGIC:
            // If user manually scrolled down to the end, re-enable auto-scroll.
            if isAtBottom && !viewModel.isUserScrolledToBottom {
                if !isProgrammaticallyScrolling {
                    viewModel.isUserScrolledToBottom = true
                }
            }
        }
        .legacy_onChange(of: updateTicker) { _ in
            if viewModel.isUserScrolledToBottom {
                scrollToBottomWithRetries(proxy, source: "Update Ticker")
            }
        }
        .legacy_onChange(of: replayProgress) { _ in
            updateDisplayedMessages()
            if viewModel.isUserScrolledToBottom {
                scrollToBottomWithRetries(proxy, source: "Replay Progress")
            }
        }
        .onAppear {
            setupOnAppear(proxy: proxy, height: geometry.size.height)
        }
    }

    private var controlsOverlay: some View {
        VStack {
            Spacer()

            if showControls {
                controlBar
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.regularMaterial)
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            } else if shouldShowControls {
                Button((isTestRunning ? "Running..." : canReplay ? "Start Replay" : "No history to replay")) {
                    if !isTestRunning, canReplay {
                        showControls = true
                        startReplay()
                    }
                }
                .disabled(isTestRunning)
                .glassButtonStyle(primaryColor: isTestRunning ? .gray : .blue)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Helper Methods

    private func setupOnAppear(proxy: ScrollViewProxy, height: CGFloat) {
        viewModel.scrollViewHeight = height

        setupStorageCallback()
        initializeState()

        // Hardware Scroll Listener
        scrollMonitor.onScroll = { event in
            if viewModel.isUserScrolledToBottom {
                // macOS "Natural Scrolling": deltaY > 0 means pulling content down (scrolling UP in history)
                // Threshold 1.0 filters out micro-movements from resting fingers
                if event.scrollingDeltaY > 1.0 {
                    viewModel.isUserScrolledToBottom = false
                    isProgrammaticallyScrolling = false
                }
            }
        }

        let hasTestResults = mappedMessages.contains { message in
            if case .testResult(_, _) = message { return true }
            return false
        }

        // Default to locked at bottom on open
        viewModel.isUserScrolledToBottom = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if viewModel.isUserScrolledToBottom {
                scrollToBottomWithRetries(proxy, source: "Initial onAppear")
            }
        }
    }

    private func cleanup() {
        stopReplay()
        hideReplayView()

        for handle in observerHandles {
            handle.cancel()
        }
        observerHandles.removeAll()
    }

    private func updateDisplayedMessages() {
        let actualMessageIndex = calculateActualMessageIndex(from: Int(replayProgress))
        let maxIndex = actualMessageIndex + Self.hiddenMessagesCount

        let displayedEnhancedHistory = Array(runHistory.enhancedChatHistory.prefix(maxIndex))
        let filteredEnhancedHistory = getFilteredEnhancedMessages(from: displayedEnhancedHistory)

        let displayedChatHistoryForScreenshot = displayedEnhancedHistory.map { $0.toChatMessage(imageType: .base64) }

        if showControls {
            updateReplayScreenshot(for: displayedChatHistoryForScreenshot)
        } else {
            replayState.reset()
        }

        let messageMapper = MessageMapper(errorCapturer: errorCapturer)
        displayedMessages = messageMapper.mapMessages(filteredEnhancedHistory)
        updateTicker += 1
    }

    private func scrollToBottomWithRetries(_ proxy: ScrollViewProxy, source: String) {
        guard viewModel.isUserScrolledToBottom else { return }

        isProgrammaticallyScrolling = true
        proxy.scrollTo("bottom", anchor: .bottom)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isProgrammaticallyScrolling = false
            if self.viewModel.isUserScrolledToBottom {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private func calculateActualMessageIndex(from progressIndex: Int) -> Int {
        let filteredMessages = getFilteredEnhancedMessages(from: runHistory.enhancedChatHistory)

        guard progressIndex > 0 else {
            return 0
        }

        return iterateLogicalSteps(in: filteredMessages, maxSteps: progressIndex).messageIndex
    }

    private func getFilteredEnhancedMessages(from messages: [EnhancedMessage]) -> [EnhancedMessage] {
        return messages.count > Self.hiddenMessagesCount ? Array(messages.dropFirst(Self.hiddenMessagesCount)) : []
    }

    private func iterateLogicalSteps(in messages: [EnhancedMessage], maxSteps: Int?) -> (stepCount: Int, messageIndex: Int) {
        var stepCount = 0
        var messageIndex = 0

        while messageIndex < messages.count {
            if let maxSteps = maxSteps, stepCount >= maxSteps {
                break
            }
            if messageIndex + 2 < messages.count,
               case .user = messages[messageIndex],
               case .assistant = messages[messageIndex + 1],
               case .tool = messages[messageIndex + 2]
            {
                messageIndex += 3
                stepCount += 1
            }
            else if messageIndex + 1 < messages.count,
                    case .user = messages[messageIndex],
                    case .assistant = messages[messageIndex + 1]
            {
                messageIndex += 2
                stepCount += 1
            }
            else if messageIndex + 1 < messages.count,
                    case .assistant = messages[messageIndex],
                    case .tool = messages[messageIndex + 1]
            {
                messageIndex += 2
                stepCount += 1
            }
            else {
                messageIndex += 1
                stepCount += 1
            }
        }

        return (stepCount: stepCount, messageIndex: messageIndex)
    }

    private func getFilteredMessages(from messages: [ChatQuery.ChatCompletionMessageParam]) -> [ChatQuery.ChatCompletionMessageParam] {
        return messages.count > Self.hiddenMessagesCount ? Array(messages.dropFirst(Self.hiddenMessagesCount)) : []
    }

    private func updateReplayScreenshot(for messages: [ChatQuery.ChatCompletionMessageParam]) {
        var latestScreenshot: PlatformImage? = nil
        var latestIndex: Int? = nil

        for (idx, message) in messages.enumerated().reversed() {
            if case .user(let userParam) = message,
               case .contentParts(let contentParts) = userParam.content
            {
                for part in contentParts {
                    if case .image(let imageParam) = part,
                       let imageData = Data(fromImageDataString: imageParam.imageUrl.url),
                       let screenshot = PlatformImage(data: imageData)
                    {
                        latestScreenshot = screenshot
                        latestIndex = idx
                        break
                    }
                }
                if latestScreenshot != nil { break }
            }
        }

        replayState.screenshot = latestScreenshot

        guard let startIndex = latestIndex else {
            replayState.markers = []
            return
        }

        var markers: [ReplayMarker] = []
        if startIndex + 1 < messages.count {
            for i in (startIndex + 1)..<messages.count {
                let msg = messages[i]
                if case .user(let userParam) = msg,
                   case .contentParts(let parts) = userParam.content,
                   parts.contains(where: { if case .image = $0 { return true } else { return false } })
                {
                    break
                }
                if case .tool(let toolParam) = msg {
                    if let details = parseCoordinatesFromToolResponse(toolParam) {
                        markers.append(
                            ReplayMarker(
                                x: details.coord.x,
                                y: details.coord.y,
                                kind: details.kind,
                                direction: details.direction,
                                amount: details.amount,
                                scale: details.scale
                            )
                        )
                    }
                }
            }
        }
        replayState.markers = markers
    }

    private func parseCoordinatesFromToolResponse(_ toolParam: ChatQuery.ChatCompletionMessageParam.ToolMessageParam) -> (coord: (x: Int, y: Int), kind: ReplayMarker.Kind, direction: String?, amount: Double?, scale: Double?)? {
        if case .textContent(let text) = toolParam.content,
           let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let coordinates = json["coordinates"] as? [String: Any],
           let x = coordinates["x"] as? Int,
           let y = coordinates["y"] as? Int
        {
            let direction = json["direction"] as? String
            let amount = json["amount"] as? Double
            let scale = json["scale"] as? Double

            let kind: ReplayMarker.Kind
            if scale != nil {
                kind = .zoom
            } else if direction != nil || amount != nil {
                kind = .move
            } else {
                kind = .tap
            }

            return (coord: (x, y), kind: kind, direction: direction, amount: amount, scale: scale)
        }
        return nil
    }

    private func updateControlsVisibility() {
        shouldShowControls = !mappedMessages.isEmpty
    }

    private var controlBar: some View {
        HStack(spacing: 16) {
            Button(action: toggleReplay) {
                Image(systemName: isReplaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .foregroundColor(.primary)
            }
            .buttonStyle(PlainButtonStyle())

            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { replayProgress },
                        set: { newValue in
                            let oldValue = replayProgress
                            userMovedSlider = true
                            replayProgress = newValue
                            if isReplaying {
                                pauseReplay()
                            }
                        }
                    ),
                    in: 0...Double(effectiveMessageCount()),
                    step: 1
                )

                HStack {
                    Text("0").font(.caption2).foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(replayProgress))/\(effectiveMessageCount())").font(.caption2).foregroundColor(.secondary)
                    Spacer()
                    Text("\(effectiveMessageCount())").font(.caption2).foregroundColor(.secondary)
                }
            }

            Button("Cancel") {
                cancelReplay()
            }
            .buttonStyle(.bordered)
        }
    }

    private func toggleReplay() {
        if isReplaying {
            pauseReplay()
        } else {
            startReplay()
        }
    }

    private func startReplay() {
        guard !mappedMessages.isEmpty else { return }
        isReplaying = true
        userMovedSlider = false
        if replayProgress >= Double(effectiveMessageCount()) {
            replayProgress = 0
        }
        replayTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            if replayProgress < Double(effectiveMessageCount()) {
                replayProgress += 1
            } else {
                stopReplay()
            }
        }
    }

    private func pauseReplay() {
        isReplaying = false
        replayTimer?.invalidate()
        replayTimer = nil
    }

    private func stopReplay() {
        pauseReplay()
        if !userMovedSlider {
            replayProgress = Double(effectiveMessageCount())
        }
    }

    private func cancelReplay() {
        stopReplay()
        hideReplayView()
    }

    private func hideReplayView() {
        showControls = false
        replayState.reset()
    }

    private func setupStorageCallback() {
        for handle in observerHandles { handle.cancel() }
        observerHandles.removeAll()

        let observation = RunHistoryObservation(history: runHistory)
        observation.observeHistory {
            DispatchQueue.main.async {
                let newHistoryCount = runHistory.enhancedChatHistory.count
                let didReset = newHistoryCount <= 1 && !mappedMessages.isEmpty
                if didReset { viewModel.isUserScrolledToBottom = true }
                updateMappedMessages()
                updateControlsVisibility()
                if !isReplaying { replayProgress = Double(effectiveMessageCount()) }
                updateDisplayedMessages()
            }
        }

        observation.observeRunState { inProgress in
            DispatchQueue.main.async {
                isTestRunning = inProgress
                currentRunStartTime = runHistory.getCurrentRunStartTime()
                if inProgress {
                    stopReplay()
                    hideReplayView()
                    viewModel.isUserScrolledToBottom = true
                } else {
                    replayProgress = Double(effectiveMessageCount())
                    updateDisplayedMessages()
                }
            }
        }
        observerHandles.append(observation)
    }

    private func initializeState() {
        isTestRunning = runHistory.isRunInProgress()
        currentRunStartTime = runHistory.getCurrentRunStartTime()
        updateMappedMessages()
        updateControlsVisibility()
        replayProgress = Double(effectiveMessageCount())
        updateDisplayedMessages()
        if !canReplay || isTestRunning {
            viewModel.isUserScrolledToBottom = true
        }
    }

    private func updateMappedMessages() {
        let filteredEnhancedHistory = getFilteredEnhancedMessages(from: runHistory.enhancedChatHistory)
        let messageMapper = MessageMapper(errorCapturer: errorCapturer)
        mappedMessages = messageMapper.mapMessages(filteredEnhancedHistory)
    }
}

// MARK: - Mapped Message View

struct MappedMessageView: View {
    let mappedMessage: MappedMessage
    let isLast: Bool
    let isTestRunning: Bool
    let currentRunStartTime: Date?
    let availableWidth: CGFloat

    var body: some View {
        switch mappedMessage {
        case .single(let message, _):
            if case .user(_) = message {
                // For single user messages, align screenshot to left
                HStack {
                    ChatMessageView(message: message)
                    Spacer()
                }
            } else {
                ChatMessageView(message: message)
            }

        case .assistantStep(let stepInfo):
            AssistantStepView(
                stepInfo: stepInfo,
                isLast: isLast,
                isTestRunning: isTestRunning,
                currentRunStartTime: currentRunStartTime,
                availableWidth: availableWidth
            )

        case .partialAssistantStep(
            let userMessage,
            let assistantMessage,
            let originalUserMessage,
            let userTimestamp,
            let assistantTimestamp):
            let explicitAssistant = assistantMessage ?? .assistant(
                ChatQuery.ChatCompletionMessageParam.AssistantMessageParam(content: .textContent(""))
            )

            AssistantStepView(
                stepInfo: AssistantStepInfo(
                    userMessage: userMessage,
                    assistantMessage: explicitAssistant,
                    toolResponse: nil,
                    originalUserMessage: originalUserMessage,
                    userTimestamp: userTimestamp,
                    assistantTimestamp: assistantTimestamp ?? Date(),
                    toolTimestamp: nil
                ),
                isLast: isLast,
                isTestRunning: isTestRunning,
                currentRunStartTime: currentRunStartTime,
                availableWidth: availableWidth
            )

        case .testResult(let testResult, let duration):
            TestResultView(testResult: testResult, duration: duration)
        }
    }
}

// MARK: - Assistant Step View

struct AssistantStepView: View {
    let stepInfo: AssistantStepInfo
    let isLast: Bool
    let isTestRunning: Bool
    let currentRunStartTime: Date?
    let availableWidth: CGFloat

    private var isActiveStream: Bool {
        return isTestRunning && isLast
    }

    private var assistantHasContent: Bool {
        if case .assistant(let param) = stepInfo.assistantMessage,
           case .textContent(let text) = param.content,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return false
    }

    private var userInstruction: String? {
        guard let message = stepInfo.userMessage, case .user(let param) = message else { return nil }

        switch param.content {
        case .string(let str):
            return str
        case .contentParts(let parts):
            // Find the first text part
            for part in parts {
                if case .text(let textParam) = part {
                    return textParam.text
                }
            }
        }
        return nil
    }

    /// Computes the layout choice based on the provided width.
    private var useHorizontalLayout: Bool {
        return availableWidth >= horizontalLayoutWidthThreshold
    }

    private let horizontalLayoutWidthThreshold: CGFloat = 350.0
    private let horizontalSpacing: CGFloat = 16
    private let verticalSpacing: CGFloat = 12
    private let imageWidth: CGFloat = 100

    var body: some View {
        let layout = useHorizontalLayout ?
        AnyLayout(HStackLayout(alignment: .top, spacing: horizontalSpacing)) :
        AnyLayout(VStackLayout(alignment: .leading, spacing: verticalSpacing))

        VStack(alignment: .leading, spacing: 12) {

            layout {
                imageContentView

                if assistantHasContent {
                    AssistantContentView(
                        message: stepInfo.assistantMessage,
                        isStreaming: isActiveStream
                    )
                    .transition(.opacity)
                } else if let instruction = userInstruction {
                    // Placeholder View: Displays User's Intent
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Instruction:")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)

                        Text(instruction)
                            .font(.body)
                            .foregroundColor(.primary)
                            .italic()
                    }
                    .padding(.vertical, 2)
                    .transition(.opacity)
                }
            }

            // Tool calls and responses below
            VStack(alignment: .leading, spacing: 8) {
                if case .assistant(let assistantParam) = stepInfo.assistantMessage,
                   let toolCalls = assistantParam.toolCalls, !toolCalls.isEmpty
                {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(toolCalls.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 4) {
                                ToolCallView(toolCall: toolCalls[index])

                                // Show tool response if available
                                if let toolResponse = stepInfo.toolResponse,
                                   case .tool(let toolParam) = toolResponse
                                {
                                    ToolResponseView(toolResponse: toolParam)
                                }
                            }
                        }
                    }
                }
            }
            HStack {
                Spacer()
                timerView
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.green.opacity(0.1))
        )
        .animation(.default, value: assistantHasContent)
    }

    @ViewBuilder
    private var imageContentView: some View {
        if let original = stepInfo.originalUserMessage {
            UserImageContentView(enhancedMessage: original)
                .frame(width: imageWidth)
        } else if let userMessage = stepInfo.userMessage {
            UserImageContentView(message: userMessage)
                .frame(width: imageWidth)
        } else {
            EmptyImagePlaceholderView()
        }
    }

    @ViewBuilder
    private var timerView: some View {
        if isLast, isTestRunning,
           let startTime = currentRunStartTime,
           stepInfo.assistantTimestamp > startTime {
            LiveTimerView(startTime: stepInfo.assistantTimestamp)
        } else if let duration = stepInfo.executionDuration {
            StaticTimerView(duration: duration)
        } else {
            EmptyView()
        }
    }
}

// MARK: - Content Views

struct UserImageContentView: View {
    let message: ChatQuery.ChatCompletionMessageParam?
    var enhancedMessage: EnhancedMessage?

    init(message: ChatQuery.ChatCompletionMessageParam) {
        self.message = message
        self.enhancedMessage = nil
    }

    init(enhancedMessage: EnhancedMessage) {
        self.message = nil
        self.enhancedMessage = enhancedMessage
    }

    var body: some View {
        // SCENARIO 1: We have an EnhancedMessage object (Live or Loaded)
        if let enhanced = enhancedMessage {
            if case .user(let userParam, let enhancedParts, _) = enhanced {
                if let parts = enhancedParts {
                    // 1a. Live Run: Use Optimized Enhanced Parts
                    // Iterating 0..<count with a helper function solves the ViewBuilder type errors
                    ForEach(0..<parts.count, id: \.self) { index in
                        renderEnhancedPart(parts[index])
                    }
                } else {
                    // 1b. Loaded History: No enhanced parts, but data is in the UserParam
                    renderContentParts(from: userParam)
                }
            }
        }
        // SCENARIO 2: Legacy Fallback (Standard OpenAI Message)
        else if let message = message, case .user(let userParam) = message {
            renderContentParts(from: userParam)
        }
    }

    /// Helper to safely unpack EnhancedContentPart without confusing the ViewBuilder
    @ViewBuilder
    private func renderEnhancedPart(_ part: EnhancedContentPart) -> some View {
        if case .imageWithData(_, let base64String) = part {
            VisionPartView(base64String: base64String)
        }
    }

    /// Helper to render standard OpenAI content parts
    private func renderContentParts(from userParam: ChatQuery.ChatCompletionMessageParam.UserMessageParam) -> some View {
        Group {
            switch userParam.content {
            case .contentParts(let contentParts):
                ForEach(contentParts.indices, id: \.self) { index in
                    if case .image(_) = contentParts[index] {
                        VisionPartView(part: contentParts[index])
                    }
                }
            default:
                EmptyView()
            }
        }
    }
}

struct EmptyImagePlaceholderView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.08))
            .frame(width: 100, height: 120)
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: "photo")
                        .foregroundColor(.secondary)
                    Text("No screenshot")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            )
    }
}

struct UserContentView: View {
    let message: ChatQuery.ChatCompletionMessageParam

    var body: some View {
        if case .user(let userParam) = message {
            switch userParam.content {
            case .string(let text):
                Markdown(text)
                    .markdownTheme(.docC)
                    .textSelection(.enabled)
            case .contentParts(let contentParts):
                ForEach(contentParts.indices, id: \.self) { index in
                    VisionPartView(part: contentParts[index])
                }
            @unknown default:
                Text("Unknown content type")
                    .italic()
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

struct AssistantContentView: View {
    let message: ChatQuery.ChatCompletionMessageParam
    let isStreaming: Bool

    var body: some View {
        if case .assistant(let assistantParam) = message,
           case .textContent(let text) = assistantParam.content
        {
            StabilizedMarkdownView(text: text, isStreaming: isStreaming)
        }
    }
}

struct ToolResponseView: View {
    let toolResponse: ChatQuery.ChatCompletionMessageParam.ToolMessageParam

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Response:")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            if case .textContent(let text) = toolResponse.content {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    )
            }
        }
    }
}

struct ChatMessageView: View {
    let message: ChatQuery.ChatCompletionMessageParam

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                MessageRoleTag(role: messageRole)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                // Display content based on message type
                switch message {
                case .system(let systemParam):
                    if case .textContent(let text) = systemParam.content {
                        Markdown(text)
                            .markdownTheme(.docC)
                            .textSelection(.enabled)
                    }

                case .user(let userParam):
                    switch userParam.content {
                    case .string(let text):
                        Markdown(text)
                            .markdownTheme(.docC)
                            .textSelection(.enabled)
                    case .contentParts(let contentParts):
                        ForEach(contentParts.indices, id: \.self) { index in
                            VisionPartView(part: contentParts[index])
                        }
                    @unknown default:
                        Text("Unknown content type")
                            .italic()
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }

                case .assistant(let assistantParam):
                    if case .textContent(let content) = assistantParam.content {
                        StabilizedMarkdownView(text: content, isStreaming: false)
                    }

                    if let toolCalls = assistantParam.toolCalls, !toolCalls.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tool Calls:")
                                .font(.caption)
                                .fontWeight(.semibold)

                            ForEach(toolCalls.indices, id: \.self) { index in
                                ToolCallView(toolCall: toolCalls[index])
                            }
                        }
                    }

                case .tool(let toolParam):
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tool Response:")
                            .font(.caption)
                            .fontWeight(.semibold)
                        if case let .textContent(text) = toolParam.content {
                            Markdown(text)
                                .markdownTheme(.docC)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }

                case .developer(let developerParam):
                    if case let .textContent(text) = developerParam.content {
                        Markdown(text)
                            .markdownTheme(.docC)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(messageBackgroundColor.opacity(0.3))
        )
    }

    private var messageRole: String {
        switch message {
        case .system(_): return "system"
        case .user(_): return "user"
        case .assistant(_): return "assistant"
        case .tool(_): return "tool"
        case .developer(_): return "developer"
        }
    }

    private var messageBackgroundColor: Color {
        switch message {
        case .system(_): return .purple
        case .user(_): return .blue
        case .assistant(_): return .green
        case .tool(_): return .orange
        case .developer(_): return .red
        }
    }
}

struct MessageRoleTag: View {
    let role: String

    var body: some View {
        Text(role.uppercased())
            .font(.caption)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(tagColor)
            )
    }

    private var tagColor: Color {
        switch role {
        case "system", "developer": return .purple
        case "user": return .blue
        case "assistant": return .green
        case "tool": return .orange
        default: return .gray
        }
    }
}

struct VisionPartView: View, Loggable {

    // Both must be optional so we can initialize one and leave the other nil
    let part: ChatQuery.ChatCompletionMessageParam.UserMessageParam.Content.ContentPart?
    let base64String: String?

    // Init 1: From Standard OpenAI Part
    init(part: ChatQuery.ChatCompletionMessageParam.UserMessageParam.Content.ContentPart) {
        self.part = part
        self.base64String = nil
    }

    // Init 2: From Raw Base64 String (The one causing your error)
    init(base64String: String) {
        self.base64String = base64String
        self.part = nil
    }

    var body: some View {
        if let base64String = base64String {
            // Direct decoding using the extension from SingletonStorage.swift
            if let imageData = Data(base64JpegURLString: base64String) {
                imageView(for: imageData)
            } else {
                errorView
            }
        } else if let part = part {
            switch part {
            case .text(let textParam):
                Markdown(textParam.text)
                    .markdownTheme(.docC)
                    .textSelection(.enabled)

            case .image(let imageParam):
                // Legacy decoding
                if let imageData = Data(base64JpegURLString: imageParam.imageUrl.url) {
                    imageView(for: imageData)
                } else {
                    errorView
                }
            default:
                Text("Unsupported content type")
                    .italic()
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func imageView(for imageData: Data) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Image:")
                .font(.caption)
                .fontWeight(.semibold)
                .textSelection(.enabled)

#if os(iOS)
            if let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(minWidth: 50, minHeight: 50)
                    .frame(maxHeight: 200)
                    .cornerRadius(8)
            }
#elseif os(macOS)
            if let nsImage = NSImage(data: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(minWidth: 50, minHeight: 50)
                    .frame(maxHeight: 200)
                    .cornerRadius(8)
            } else {
                decodeErrorView
            }
#endif
        }
    }

    private var errorView: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.3))
            .frame(height: 200)
            .overlay(
                Text("Image not available")
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            )
    }

    private var decodeErrorView: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.red.opacity(0.1))
            .frame(height: 100)
            .overlay(
                Text("Bad Image Data")
                    .font(.caption)
                    .foregroundColor(.red)
            )
    }
}

struct ToolCallView: View {
    let toolCall: ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pythonCallString)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.1))
                )
        }
    }

    private var pythonCallString: String {
        let functionName = toolCall.function.name
        let argumentsString = toolCall.function.arguments
        if let data = argumentsString.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           !dict.isEmpty
        {
            let params = dict.map { key, value in
                let valueString: String
                if let v = value as? String {
                    valueString = "\"\(v)\""
                } else {
                    valueString = String(describing: value)
                }
                return "\(key)=\(valueString)"
            }.joined(separator: ", ")
            return "\(functionName)(\(params))"
        } else {
            return "\(functionName)()"
        }
    }
}

// MARK: - Timer Views

/// A view that displays a static, pre-calculated duration.
struct StaticTimerView: View {
    let duration: TimeInterval

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "timer")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(String(format: "%.1f s", duration))
                .font(.system(.caption, design: .monospaced).weight(.medium)) // Monospaced for stable width
                .foregroundColor(.secondary)
        }
    }
}

/// A view that displays a live, ticking timer from a given start date.
struct LiveTimerView: View {
    let startTime: Date
    @State private var duration: TimeInterval = 0

    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "timer")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(String(format: "%.1f s", duration))
                .font(.system(.caption, design: .monospaced).weight(.medium)) // Monospaced for stable width
                .foregroundColor(.secondary)
                .onReceive(timer) { _ in
                    duration = Date().timeIntervalSince(startTime)
                }
        }
        .onAppear {
            duration = Date().timeIntervalSince(startTime)
        }
    }
}

struct TotalTimeView: View {
    let duration: TimeInterval

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "timer")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Total: ")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            Text(formattedDuration)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .foregroundColor(.secondary)
        }
    }

    private var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = duration.truncatingRemainder(dividingBy: 60)

        if minutes > 0 {
            return String(format: "%dm %.1fs", minutes, seconds)
        } else {
            return String(format: "%.1f s", seconds)
        }
    }
}

// MARK: - Scroll Position Tracking

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// Tracks the total content height of the scrollable area so we can re-scroll when it grows
private struct ContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private extension ChatQuery.ChatCompletionMessageParam {
    var containsImage: Bool {
        guard case .user(let userMessage) = self else { return false }
        guard case .contentParts(let parts) = userMessage.content else { return false }

        for part in parts {
            if case .image = part {
                return true
            }
        }

        return false
    }
}

// MARK: - Test Result View

struct TestResultView: View {
    let testResult: TestResult
    let duration: TimeInterval?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with test result status
            HStack {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Test Result")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .textSelection(.enabled)

                    Text(testResult.testResult.displayText)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(statusColor)
                        .textSelection(.enabled)
                }

                Spacer()

                // Objective achievement indicator
                HStack(spacing: 4) {
                    Image(systemName: testResult.testObjectiveAchieved ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(testResult.testObjectiveAchieved ? .green : .red)
                    Text("Objective \(testResult.testObjectiveAchieved ? "Achieved" : "Failed")")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(testResult.testObjectiveAchieved ? .green : .red)
                        .textSelection(.enabled)
                }
            }

            Divider()

            // Steps followed section
            HStack(spacing: 8) {
                Image(systemName: testResult.stepsFollowedExactly ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(testResult.stepsFollowedExactly ? .green : .orange)
                    .font(.subheadline)

                Text(testResult.stepsFollowedExactly ? "Steps followed exactly" : "Test diverged from exact steps")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(testResult.stepsFollowedExactly ? .green : .orange)
                    .textSelection(.enabled)

                Spacer()
            }

            // Adaptations made section
            if !testResult.adaptationsMade.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Adaptations Made", systemImage: "arrow.triangle.branch")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .textSelection(.enabled)

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(testResult.adaptationsMade, id: \.self) { adaptation in
                            HStack(alignment: .top, spacing: 8) {
                                if testResult.adaptationsMade.count > 1 {
                                    Text("•")
                                        .foregroundColor(.secondary)
                                        .font(.body)
                                }

                                Text(adaptation)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)

                                Spacer()
                            }
                        }
                    }
                }
            }

            // Final state section
            if !testResult.finalStateDescription.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Final State", systemImage: "flag.checkered")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .textSelection(.enabled)

                    Text(testResult.finalStateDescription)
                        .font(.body)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }

            // Comments section
            if !testResult.comments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Comments", systemImage: "text.bubble")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .textSelection(.enabled)

                    Text(testResult.comments)
                        .font(.body)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }

            if let duration = duration {
                HStack {
                    Spacer()
                    TotalTimeView(duration: duration)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(statusColor.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(statusColor.opacity(0.3), lineWidth: 2)
                )
        )
    }

    private var statusColor: Color {
        testResult.testResult.color
    }

    private var statusIcon: String {
        testResult.testResult.icon
    }
}
