//
//  AssistantView.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 12.06.2025.
//

import SwiftUI
import OpenAI

struct AssistantView: View {
    @ObservedObject var chatReplayViewModel: ChatReplayViewModel
    @ObservedObject var replayState: ReplayState
    
    let runHistory: RunHistory
    let errorCapturer: ErrorCapturing

    var body: some View {
        VStack(spacing: 16) {
            Group {
                ChatReplayView(
                    fileURL: nil,
                    viewModel: chatReplayViewModel,
                    runHistory: runHistory,
                    replayState: replayState,
                    errorCapturer: errorCapturer
                )
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.regularMaterial)
                            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                    )
            }
        }
        .padding(8)
        .frame(minWidth: 400, idealWidth: 400, maxWidth: 400)
    }
}

// MARK: - Preview

struct AssistantView_Previews: PreviewProvider {
    static var previews: some View {
        // Set up sample actions
        let sampleActions = [
            Action(
                action: "Take a screenshot of the current screen",
                parsedAction: "screenshot()",
                isLoading: false
            ),
            Action(
                action: "Tap on the login button",
                parsedAction: "tap(element: \"login_button\")",
                isLoading: false,
                warning: "Element might not be visible"
            ),
            Action(
                action: "Enter username 'testuser' in the username field",
                parsedAction: "type(element: \"username_field\", text: \"testuser\")",
                isLoading: true
            ),
            Action(
                action: "Swipe down to refresh the content",
                parsedAction: "swipe(direction: \"down\", distance: 200)",
                isLoading: false
            ),
            Action(
                action: "Verify that welcome message appears",
                parsedAction: "assert(element: \"welcome_message\", visible: true)",
                isLoading: false
            )
        ]

        // Set up sample chat history
        let sampleMessages: [ChatQuery.ChatCompletionMessageParam] = [
            .system(.init(content: .textContent("You are a helpful assistant that helps with iOS app testing. You can take screenshots, tap elements, enter text, and verify UI elements."))),

                .user(.init(content: .string("I need help testing a login flow. Can you start by taking a screenshot?"))),

                .assistant(.init(
                    content: .textContent("I'll help you test the login flow. Let me start by taking a screenshot to see the current state of the app."),
                    audio: nil,
                    name: "assistant",
                    toolCalls: [
                        .init(
                            id: "call_screenshot_1",
                            function: .init(
                                arguments: "{}",
                                name: "screenshot"
                            )
                        )
                    ]
                )),

                .tool(.init(
                    content: .textContent("{\"success\": true, \"message\": \"Screenshot taken successfully\", \"image\": \"base64_image_data\"}"),
                    toolCallId: "call_screenshot_1"
                )),

                .assistant(.init(
                    content: .textContent("""
                Perfect! I can see the login screen. I notice there are **username** and **password** fields, along with a **Login** button. 
                
                Let me proceed with the test by:
                1. Entering a test username
                2. Entering a test password  
                3. Tapping the login button
                
                Let me start by entering the username:
                """),
                    audio: nil,
                    name: "assistant",
                    toolCalls: [
                        .init(
                            id: "call_type_1",
                            function: .init(
                                arguments: "{\"element\": \"username_field\", \"text\": \"testuser\"}",
                                name: "type"
                            )
                        )
                    ]
                )),

                .tool(.init(
                    content: .textContent("{\"success\": true, \"message\": \"Text entered successfully in username field\"}"),
                    toolCallId: "call_type_1"
                )),

                .user(.init(content: .string("Great! Now please enter the password 'password123' and then tap login."))),

                .assistant(.init(
                    content: .textContent("Now I'll enter the password and tap the login button to complete the flow."),
                    audio: nil,
                    name: "assistant",
                    toolCalls: [
                        .init(
                            id: "call_type_2",
                            function: .init(
                                arguments: "{\"element\": \"password_field\", \"text\": \"password123\"}",
                                name: "type"
                            )
                        )
                    ]
                )),

                .tool(.init(
                    content: .textContent("{\"success\": true, \"message\": \"Password entered successfully\"}"),
                    toolCallId: "call_type_2"
                ))
        ]

        let runStorage = RunStorage()
        let actionsText = sampleActions.map { $0.parsedAction ?? $0.action }.joined(separator: "\n")
        runStorage.setSingleTest(actionsText, testURL: URL(fileURLWithPath: "/tmp/sample.test"))
        let previewHistory = RunHistory()
        previewHistory.setHistory(sampleMessages)
        let replayState = ReplayState()

        let chatReplayViewModel = ChatReplayViewModel()
        let errorCapturer = PreviewServices.errorCapturer

        return AssistantView(
            chatReplayViewModel: chatReplayViewModel,
            replayState: replayState,
            runHistory: previewHistory,
            errorCapturer: errorCapturer
        )
            .frame(width: 400, height: 600)
            .environmentObject(runStorage)
            .environmentObject(errorCapturer)
    }
}
