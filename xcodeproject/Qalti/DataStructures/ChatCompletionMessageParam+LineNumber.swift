import Foundation
import OpenAI

extension ChatQuery.ChatCompletionMessageParam {
    func extractLineNumber() -> Int? {
        if case .assistant(let assistantParam) = self,
               case .textContent(let text) = assistantParam.content {
                // Try pattern: "line X" (case-insensitive)
                if let match = text.range(of: #"\bline\s+(\d+)\b"#, options: [.regularExpression, .caseInsensitive]) {
                    let matchedString = String(text[match])
                    if let numberMatch = matchedString.range(of: #"\d+"#, options: .regularExpression) {
                        let numberString = String(matchedString[numberMatch])
                        if let parsed = Int(numberString) {
                            return max(0, parsed - 1)
                        }
                    }
                }
                // Try pattern: "X/Y"
                if let slashMatch = text.range(of: #"\b(\d+)\s*/\s*(\d+)\b"#, options: .regularExpression) {
                    let prefix = String(text[slashMatch])
                    if let firstNumMatch = prefix.range(of: #"^\d+"#, options: .regularExpression) {
                        let firstNum = String(prefix[firstNumMatch])
                        if let parsed = Int(firstNum) {
                            return max(0, parsed - 1)
                        }
                    }
                }
            return nil
        }
        return nil
    }
}


