import Foundation

extension IOSRuntime {

    static func compareCommands(_ lhs: String, _ rhs: String, ignoreCreepAmount: Bool = false) -> Bool {
        guard let lhsParsed = try? parseCommand(from: lhs), let rhsParsed = try? parseCommand(from: rhs) else { return false }
        guard lhsParsed.name == rhsParsed.name else { return false }
        guard lhsParsed.args.count == rhsParsed.args.count else { return false }

        let lhsArgs = (ignoreCreepAmount && lhsParsed.name == "creep") ? lhsParsed.args.dropLast() : lhsParsed.args
        let rhsArgs = (ignoreCreepAmount && rhsParsed.name == "creep") ? rhsParsed.args.dropLast() : rhsParsed.args

        for (lhsArg, rhsArg) in zip(lhsArgs, rhsArgs) {
            if let stringLhsArg = lhsArg as? String, let stringRhsArg = rhsArg as? String {
                guard stringLhsArg == stringRhsArg else { return false }
                continue
            }

            if let intLhsArg = lhsArg as? Int, let intRhsArg = rhsArg as? Int {
                guard intLhsArg == intRhsArg else { return false }
                continue
            }

            if let boolLhsArg = lhsArg as? Bool, let boolRhsArg = rhsArg as? Bool {
                guard boolLhsArg == boolRhsArg else { return false }
                continue
            }

            return false
        }

        return true
    }

    static func parseCommand(from commandString: String) throws -> (name: String, args: [Any], formattedCommand: NSAttributedString) {
        let pattern = #"^(\w+)(\()(.*)(\))(\s*(?:#|//)\s*.*)?$"#
        let regex = try NSRegularExpression(pattern: pattern)
        guard let match = regex.firstMatch(in: commandString, range: NSRange(commandString.startIndex..., in: commandString)) else {
            throw NSError(domain: "Command Parsing", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid command format: \(commandString)"])
        }

        // Create mutable attributed string for syntax highlighting
        var attributedString = NSMutableAttributedString(string: commandString)
        let fullRange = NSRange(location: 0, length: commandString.count)

        // Set default text attributes
        attributedString.addAttribute(.foregroundColor, value: PlatformColor.label, range: fullRange)

        // Group 1: Command name - highlight in blue and bold
        let nameRange = match.range(at: 1)
        let name = (commandString as NSString).substring(with: nameRange)
        attributedString.addAttribute(.foregroundColor, value: PlatformColor.systemBlue, range: nameRange)

        // Group 2: Opening parenthesis - highlight in gray
        let openParenRange = match.range(at: 2)
        attributedString.addAttribute(.foregroundColor, value: PlatformColor.systemGray, range: openParenRange)

        // Group 4: Closing parenthesis - highlight in gray
        let closeParenRange = match.range(at: 4)
        attributedString.addAttribute(.foregroundColor, value: PlatformColor.systemGray, range: closeParenRange)

        // Group 3: Arguments - parse and highlight
        let argsRange = match.range(at: 3)
        let args = try parseArguments(attributedString: &attributedString, range: argsRange)

        // Group 5: Comment (optional) - highlight in green and italic
        if match.numberOfRanges > 5 {
            let commentRange = match.range(at: 5)
            if commentRange.location != NSNotFound {
                attributedString.addAttribute(.foregroundColor, value: PlatformColor.systemGreen, range: commentRange)
            }
        }

        return (name: name, args: args, formattedCommand: attributedString)
    }

    private static func parseArguments(attributedString: inout NSMutableAttributedString, range: NSRange) throws -> [Any] {
        let argsString = (attributedString.string as NSString).substring(with: range)
        guard !argsString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        var args: [Any] = []
        var currentArg = ""
        var currentArgStart = 0
        var insideSingleQuotes = false
        var insideDoubleQuotes = false
        var escapedChar = false
        var charIndex = 0

        for char in argsString {
            if escapedChar {
                // Add the escaped character as-is
                currentArg.append(char)
                escapedChar = false
                charIndex += 1
                continue
            }

            if char == "\\" {
                // Next character should be treated as escaped
                escapedChar = true
                charIndex += 1
                continue
            }

            if char == "'", !insideDoubleQuotes {
                // Toggle the quote state and highlight quotes
                insideSingleQuotes.toggle()
                let quoteRange = NSRange(location: range.location + charIndex, length: 1)
                attributedString.addAttribute(.foregroundColor, value: PlatformColor.systemOrange, range: quoteRange)
                charIndex += 1
                continue
            }

            if char == "\"", !insideSingleQuotes {
                // Toggle the quote state and highlight quotes
                insideDoubleQuotes.toggle()
                let quoteRange = NSRange(location: range.location + charIndex, length: 1)
                attributedString.addAttribute(.foregroundColor, value: PlatformColor.systemOrange, range: quoteRange)
                charIndex += 1
                continue
            }

            if char == "," && !(insideSingleQuotes || insideDoubleQuotes) {
                // End of an argument, but only if we're not inside quotes
                let argRange = NSRange(location: range.location + currentArgStart, length: charIndex - currentArgStart)
                let value = try parseValue(attributedString: &attributedString, range: argRange, valueString: currentArg)
                args.append(value)

                // Highlight comma
                let commaRange = NSRange(location: range.location + charIndex, length: 1)
                attributedString.addAttribute(.foregroundColor, value: PlatformColor.systemGray, range: commaRange)

                currentArg = ""
                currentArgStart = charIndex + 1
            } else {
                // Add the character to the current argument
                currentArg.append(char)
            }

            charIndex += 1
        }

        // Don't forget the last argument
        if !currentArg.isEmpty {
            let argRange = NSRange(location: range.location + currentArgStart, length: charIndex - currentArgStart)
            let value = try parseValue(attributedString: &attributedString, range: argRange, valueString: currentArg)
            args.append(value)
        }

        // Check if we have unclosed quotes
        if insideSingleQuotes || insideDoubleQuotes {
            throw NSError(domain: "Argument Parsing", code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "Unclosed quotes in argument string"])
        }

        return args
    }


    private static func parseValue(attributedString: inout NSMutableAttributedString, range: NSRange, valueString: String) throws -> Any {
        let trimmed = valueString.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            throw NSError(domain: "Argument Parsing", code: -3,
                        userInfo: [NSLocalizedDescriptionKey: "Empty argument"])
        }

        // Calculate the actual content range (trimmed)
        let leadingWhitespace = valueString.count - valueString.ltrimmed().count
        let trailingWhitespace = valueString.count - valueString.rtrimmed().count
        let contentRange = NSRange(
            location: range.location + leadingWhitespace,
            length: range.length - leadingWhitespace - trailingWhitespace
        )

        if let intValue = Int(trimmed) {
            // Syntax highlight integers
            attributedString.addAttribute(.foregroundColor, value: PlatformColor.systemPurple, range: contentRange)
            return intValue
        } else if let doubleValue = Double(trimmed) {
            // Syntax highlight doubles
            attributedString.addAttribute(.foregroundColor, value: PlatformColor.systemPurple, range: contentRange)
            return doubleValue
        } else if trimmed.lowercased() == "true" {
            // Syntax highlight boolean true
            attributedString.addAttribute(.foregroundColor, value: PlatformColor.systemRed, range: contentRange)
            return true
        } else if trimmed.lowercased() == "false" {
            // Syntax highlight boolean false
            attributedString.addAttribute(.foregroundColor, value: PlatformColor.systemRed, range: contentRange)
            return false
        } else if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            if let data = trimmed.data(using: .utf8),
               let array = try? JSONSerialization.jsonObject(with: data, options: []) as? [Any]
            {
                attributedString.addAttribute(.foregroundColor, value: PlatformColor.systemOrange, range: contentRange)
                return array
            } else {
                attributedString.addAttribute(.foregroundColor, value: PlatformColor.systemOrange, range: contentRange)
                return trimmed
            }
        } else {
            // Syntax highlight strings (exclude quotes from highlighting)
            let isQuoted = (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) ||
                          (trimmed.hasPrefix("'") && trimmed.hasSuffix("'"))

            if isQuoted && trimmed.count >= 2 {
                // Highlight string content (without quotes)
                let stringContentRange = NSRange(
                    location: contentRange.location + 1,
                    length: contentRange.length - 2
                )
                if stringContentRange.length > 0 {
                    attributedString.addAttribute(.foregroundColor, value: PlatformColor.systemOrange, range: stringContentRange)
                }
                return String(trimmed.dropFirst().dropLast())
            } else {
                // Unquoted string
                attributedString.addAttribute(.foregroundColor, value: PlatformColor.systemOrange, range: contentRange)
                return trimmed
            }
        }
    }

}


private extension String {
    func ltrimmed() -> String {
        guard let index = firstIndex(where: { !$0.isWhitespace }) else {
            return ""
        }
        return String(self[index...])
    }

    func rtrimmed() -> String {
        guard let index = lastIndex(where: { !$0.isWhitespace }) else {
            return ""
        }
        return String(self[...index])
    }
}
