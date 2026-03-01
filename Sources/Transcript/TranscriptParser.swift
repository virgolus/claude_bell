import Foundation

struct TranscriptMessage: Identifiable {
    let id = UUID()
    let role: String // "user" or "assistant"
    let textContent: String
    let toolUses: [ToolUseEntry]
    let timestamp: Date?
}

struct ToolUseEntry: Identifiable {
    let id = UUID()
    let name: String
    let input: String // Pretty-printed JSON summary
}

enum TranscriptParser {

    /// Reads the last N user/assistant messages from a JSONL transcript file.
    static func parseLastMessages(from path: String, count: Int = 10) -> [TranscriptMessage] {
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }

        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }

        var messages: [TranscriptMessage] = []

        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            guard let type = json["type"] as? String,
                  (type == "user" || type == "assistant") else {
                continue
            }

            guard let message = json["message"] as? [String: Any],
                  let role = message["role"] as? String else {
                continue
            }

            let content = message["content"]
            var textParts: [String] = []
            var toolUses: [ToolUseEntry] = []

            if let contentString = content as? String {
                textParts.append(contentString)
            } else if let contentArray = content as? [[String: Any]] {
                for block in contentArray {
                    if let blockType = block["type"] as? String {
                        if blockType == "text", let text = block["text"] as? String {
                            textParts.append(text)
                        } else if blockType == "tool_use", let name = block["name"] as? String {
                            let inputSummary: String
                            if let input = block["input"] as? [String: Any] {
                                inputSummary = summarizeInput(input)
                            } else {
                                inputSummary = ""
                            }
                            toolUses.append(ToolUseEntry(name: name, input: inputSummary))
                        }
                    }
                }
            }

            let timestamp: Date?
            if let ts = json["timestamp"] as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                timestamp = formatter.date(from: ts)
            } else {
                timestamp = nil
            }

            let combinedText = textParts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !combinedText.isEmpty || !toolUses.isEmpty {
                messages.append(TranscriptMessage(
                    role: role,
                    textContent: combinedText,
                    toolUses: toolUses,
                    timestamp: timestamp
                ))
            }
        }

        // Return last N messages
        return Array(messages.suffix(count))
    }

    private static func summarizeInput(_ input: [String: Any]) -> String {
        // Show first key-value pair as summary
        var parts: [String] = []
        for (key, value) in input.sorted(by: { $0.key < $1.key }).prefix(3) {
            let valueStr = String(describing: value)
            let truncated = valueStr.count > 100 ? String(valueStr.prefix(100)) + "..." : valueStr
            parts.append("\(key): \(truncated)")
        }
        return parts.joined(separator: "\n")
    }
}
