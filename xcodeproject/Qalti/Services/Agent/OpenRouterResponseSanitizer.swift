//
//  OpenRouterResponseSanitizer.swift
//  Qalti
//

@preconcurrency import OpenAI
import Foundation

/// Repairs OpenRouter responses that are valid JSON but don't match the vendored OpenAI client's
/// strict `Codable` schema, before its decoder ever sees them.
///
/// Two shapes were observed in the wild (both from Gemini-family models via OpenRouter, both fatal
/// to the whole stream — see `docs/investigations/gemini-decoding-crash.md`):
///
/// - `service_tier` carrying a value outside `ServiceTier`'s closed enum (e.g. `"provisioned"`),
/// - a `reasoning_details` entry whose `type` arrives before the payload field that type requires
///   (e.g. `reasoning.text` with no `text` yet) on a partial delta.
///
/// Everything else passes through **byte-identical**: a line is only re-serialized when one of
/// those two patches actually applied, so this cannot perturb responses it doesn't understand.
enum OpenRouterResponseSanitizer {

    private static let dataPrefix = "data: "
    private static let lf: UInt8 = 0x0A
    private static let cr: UInt8 = 0x0D

    private static let knownServiceTiers = Set(ServiceTier.allCases.map(\.rawValue))

    /// The field each `reasoning_details` type is required to carry.
    private static let reasoningDetailRequiredKey: [String: String] = [
        "reasoning.text": "text",
        "reasoning.encrypted": "data",
        "reasoning.summary": "summary"
    ]

    /// Reassembles raw network chunks into whole SSE lines so sanitization only ever sees complete
    /// JSON, since a single `didReceive data:` call is not guaranteed to land on a line boundary.
    ///
    /// - Note: A trailing partial line is held back until its remainder arrives, and is dropped if
    ///   the stream ends without one. That matches `ServerSentEventsStreamParser`, which keeps its
    ///   own `incompleteLine` and likewise never flushes it at end of stream — so an unterminated
    ///   final line was already discarded before this type existed.
    final class StreamBuffer {
        private var buffer = Data()

        /// Returns the sanitized complete lines available from `data`, which may be empty if the
        /// chunk did not finish a line.
        func consume(_ data: Data) -> Data {
            buffer.append(data)

            var output = Data()
            while let newlineIndex = buffer.firstIndex(of: lf) {
                let line = buffer.subdata(in: buffer.startIndex..<newlineIndex)
                output.append(sanitize(line: line))
                output.append(lf)
                buffer.removeSubrange(buffer.startIndex...newlineIndex)
            }
            return output
        }
    }

    /// Patches a single SSE line. Returns it unchanged unless it is a `data:` line carrying a JSON
    /// object that matches one of the known-bad shapes.
    static func sanitize(line rawLine: Data) -> Data {
        var line = rawLine
        var hadTrailingCR = false
        if line.last == cr {
            hadTrailingCR = true
            line.removeLast()
        }

        guard let text = String(data: line, encoding: .utf8), text.hasPrefix(dataPrefix),
              let jsonData = text.dropFirst(dataPrefix.count).data(using: .utf8),
              var obj = (try? JSONSerialization.jsonObject(with: jsonData)) as? [String: Any]
        else {
            return rawLine
        }

        var mutated = false

        if let tier = obj["service_tier"] as? String, !knownServiceTiers.contains(tier) {
            obj.removeValue(forKey: "service_tier")
            mutated = true
        }

        if var choices = obj["choices"] as? [[String: Any]] {
            var patchedAnyChoice = false
            for i in choices.indices {
                guard var delta = choices[i]["delta"] as? [String: Any],
                      var details = delta["reasoning_details"] as? [[String: Any]]
                else { continue }

                var patchedThisChoice = false
                for j in details.indices {
                    guard let type = details[j]["type"] as? String,
                          let requiredKey = reasoningDetailRequiredKey[type],
                          details[j][requiredKey] == nil
                    else { continue }
                    details[j][requiredKey] = ""
                    patchedThisChoice = true
                }

                guard patchedThisChoice else { continue }
                delta["reasoning_details"] = details
                choices[i]["delta"] = delta
                patchedAnyChoice = true
            }
            if patchedAnyChoice {
                obj["choices"] = choices
                mutated = true
            }
        }

        guard mutated,
              let patchedData = try? JSONSerialization.data(withJSONObject: obj),
              let patchedText = String(data: patchedData, encoding: .utf8)
        else {
            return rawLine
        }

        var result = Data((dataPrefix + patchedText).utf8)
        if hadTrailingCR { result.append(cr) }
        return result
    }
}
