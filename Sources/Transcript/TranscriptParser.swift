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

struct QuestionOption: Identifiable {
    let id = UUID()
    let index: Int      // 1-based
    let label: String
    let description: String
    /// Literal to send when selected (e.g. "A" for letter-based options).
    /// When nil, the sender uses `"\(index)"`.
    let token: String?
}

struct ParsedQuestion: Identifiable {
    let id = UUID()
    let header: String
    let question: String
    let options: [QuestionOption]
    let multiSelect: Bool
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

    /// Parses the last AskUserQuestion from the transcript.
    /// The input.questions is an array of {question, options, multiSelect, header}.
    static func parseLastQuestions(from path: String) -> [ParsedQuestion]? {
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }

        // Scan backwards for the last AskUserQuestion tool_use
        for line in lines.reversed() {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = json["type"] as? String, type == "assistant",
                  let message = json["message"] as? [String: Any],
                  let contentArray = message["content"] as? [[String: Any]] else {
                continue
            }

            for block in contentArray {
                guard let blockType = block["type"] as? String,
                      blockType == "tool_use",
                      let name = block["name"] as? String,
                      name == "AskUserQuestion",
                      let input = block["input"] as? [String: Any] else {
                    continue
                }

                var parsed: [ParsedQuestion] = []

                // Handle questions array format
                if let questions = input["questions"] as? [[String: Any]] {
                    for q in questions {
                        guard let questionText = q["question"] as? String else { continue }
                        let header = q["header"] as? String ?? ""
                        let multiSelect = q["multiSelect"] as? Bool ?? false
                        var options: [QuestionOption] = []

                        if let opts = q["options"] as? [[String: Any]] {
                            for (i, opt) in opts.enumerated() {
                                options.append(QuestionOption(
                                    index: i + 1,
                                    label: opt["label"] as? String ?? "Option \(i + 1)",
                                    description: opt["description"] as? String ?? "",
                                    token: nil
                                ))
                            }
                        }

                        parsed.append(ParsedQuestion(
                            header: header,
                            question: questionText,
                            options: options,
                            multiSelect: multiSelect
                        ))
                    }
                }

                if !parsed.isEmpty {
                    return parsed
                }
            }
        }

        return nil
    }

    /// Parses enumerated options from the last assistant message text in the transcript.
    /// Accepts either numeric ("1. ...", "1) ...") or letter ("A. ...", "A) ...") markers,
    /// near the end of the message and preceded by a question mark.
    /// Options must be sequential (1,2,3… or A,B,C…) and all of the same type.
    static func parseNumberedOptions(from path: String) -> [ParsedQuestion]? {
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }

        for line in lines.reversed() {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = json["type"] as? String, type == "assistant",
                  let message = json["message"] as? [String: Any] else {
                continue
            }

            var textParts: [String] = []
            if let contentArray = message["content"] as? [[String: Any]] {
                for block in contentArray {
                    if let blockType = block["type"] as? String, blockType == "text",
                       let text = block["text"] as? String {
                        textParts.append(text)
                    }
                }
            } else if let contentString = message["content"] as? String {
                textParts.append(contentString)
            }

            let fullText = textParts.joined(separator: "\n")

            // Matches "1.", "1)", "A.", "A)" optionally preceded by ❯.
            let optionPattern = #"^\s*(?:❯\s*)?([A-Za-z]|\d+)[\.\)]\s+(.+)$"#
            guard let regex = try? NSRegularExpression(pattern: optionPattern, options: .anchorsMatchLines) else {
                continue
            }

            let matches = regex.matches(in: fullText, range: NSRange(fullText.startIndex..., in: fullText))
            guard matches.count >= 2 else { continue }

            // Extract markers (raw) + labels in order.
            struct Raw { let marker: String; let label: String; let range: NSRange }
            var raws: [Raw] = []
            for match in matches {
                guard let markerRange = Range(match.range(at: 1), in: fullText),
                      let textRange = Range(match.range(at: 2), in: fullText) else { continue }
                let marker = String(fullText[markerRange])
                let label = String(fullText[textRange]).trimmingCharacters(in: .whitespaces)
                raws.append(Raw(marker: marker, label: label, range: match.range))
            }
            guard raws.count >= 2 else { continue }

            // Classify: all digits, or all single letters. Reject mixed.
            let allDigits = raws.allSatisfy { Int($0.marker) != nil }
            let allLetters = raws.allSatisfy { $0.marker.count == 1 && $0.marker.unicodeScalars.first.map { CharacterSet.letters.contains($0) } == true }
            guard allDigits || allLetters else { continue }

            // Build options with sequential check (1,2,3… or A,B,C…).
            var options: [QuestionOption] = []
            var valid = true
            for (i, raw) in raws.enumerated() {
                let expectedIndex = i + 1
                let token: String?
                if allDigits {
                    guard let n = Int(raw.marker), n == expectedIndex else { valid = false; break }
                    token = nil
                } else {
                    let upper = raw.marker.uppercased()
                    let scalars = Array(upper.unicodeScalars)
                    guard let first = scalars.first,
                          let aScalar = "A".unicodeScalars.first,
                          Int(first.value) - Int(aScalar.value) + 1 == expectedIndex else {
                        valid = false; break
                    }
                    token = upper
                }
                options.append(QuestionOption(
                    index: expectedIndex,
                    label: raw.label,
                    description: "",
                    token: token
                ))
            }
            guard valid, options.count >= 2 else { continue }

            // Last option must end in the final 30% of text.
            guard let lastRange = raws.last?.range,
                  lastRange.upperBound > (fullText.utf16.count * 7 / 10) else { continue }

            // A question mark must appear before the first option.
            let firstLocation = raws[0].range.location
            let preOptionsEnd = fullText.index(fullText.startIndex, offsetBy: firstLocation, limitedBy: fullText.endIndex) ?? fullText.endIndex
            let preOptions = fullText[fullText.startIndex..<preOptionsEnd]
            guard preOptions.contains("?") else { continue }

            return [ParsedQuestion(
                header: "",
                question: "",
                options: options,
                multiSelect: false
            )]
        }

        return nil
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
