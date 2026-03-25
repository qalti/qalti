import Foundation
import OpenAI

/// Value type that represents an immutable snapshot of a RunHistory.
struct RunHistoryTranscript {
    let messages: [CodableChatMessage]

    init(messages: [CodableChatMessage]) {
        self.messages = messages
    }

    init(history: RunHistory, imageType: ImageDataType = .url) {
        self.messages = history.enhancedChatHistory.map { enhancedMessage in
            let chatMessage = enhancedMessage.toChatMessage(imageType: imageType)
            
            // Parse assistant messages to extract structured comments
            let parsedComments: [ParsedAgentComment]? = {
                if case .assistant(let assistantParam) = chatMessage,
                   case .textContent(let text) = assistantParam.content {
                    return ContentParser.parseAgentComments(text)
                }
                return nil
            }()
            
            return CodableChatMessage(
                message: chatMessage,
                timestamp: enhancedMessage.timestamp,
                parsedComments: parsedComments
            )
        }
    }

    func apply(to history: RunHistory) {
        history.loadTranscript(messages)
    }
}
