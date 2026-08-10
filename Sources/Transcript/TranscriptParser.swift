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

    /// Whether the current turn ends on a question the user still has to answer:
    /// an unanswered `AskUserQuestion`, or a plain-text message ending in '?'.
    /// Drives the choice between an interactive card and a passive completion,
    /// and is deliberately the same bound the option parsers use, so the card
    /// the hook asks for is always one the parsers can actually fill.
    static func hasPendingQuestion(at path: String) -> Bool {
        guard let transcript = Transcript(path: path),
              let latest = transcript.latestAssistantMessage() else {
            return false
        }

        if let ask = Self.askUserQuestionBlock(in: latest.message) {
            guard let toolUseId = ask["id"] as? String else { return true }
            return !transcript.isAnswered(toolUseId: toolUseId, askedAt: latest.line)
        }

        return Self.lastText(in: latest.message)?.hasSuffix("?") ?? false
    }

    /// Parses the pending AskUserQuestion of the current turn.
    /// The input.questions is an array of {question, options, multiSelect, header}.
    ///
    /// Bounded to the newest assistant message on purpose: scanning further back
    /// finds questions from earlier turns, which the user has already answered.
    /// Re-proposing one of those makes the panel ask a stale question.
    static func parseLastQuestions(from path: String) -> [ParsedQuestion]? {
        guard let transcript = Transcript(path: path),
              let latest = transcript.latestAssistantMessage(),
              let ask = Self.askUserQuestionBlock(in: latest.message),
              let input = ask["input"] as? [String: Any],
              let questions = input["questions"] as? [[String: Any]] else {
            return nil
        }

        // Answered in the terminal: the `tool_result` lands *after* the assistant
        // message that asked, so the question can still be the newest one while
        // already being settled.
        if let toolUseId = ask["id"] as? String,
           transcript.isAnswered(toolUseId: toolUseId, askedAt: latest.line) {
            return nil
        }

        var parsed: [ParsedQuestion] = []
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

        return parsed.isEmpty ? nil : parsed
    }

    /// Parses enumerated options from the newest assistant message's text.
    /// Accepts either numeric ("1. ...", "1) ...") or letter ("A. ...", "A) ...") markers,
    /// near the end of the message and preceded by a question mark.
    /// Options must be sequential (1,2,3… or A,B,C…) and all of the same type.
    ///
    /// Bounded to that one message for the same reason as `parseLastQuestions`:
    /// options scraped from an older message belong to a question the user has
    /// already answered.
    static func parseNumberedOptions(from path: String) -> [ParsedQuestion]? {
        guard let transcript = Transcript(path: path),
              let latest = transcript.latestAssistantMessage() else {
            return nil
        }

        let fullText = Self.allText(in: latest.message)

        // Matches "1.", "1)", "A.", "A)" optionally preceded by ❯.
        let optionPattern = #"^\s*(?:❯\s*)?([A-Za-z]|\d+)[\.\)]\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: optionPattern, options: .anchorsMatchLines) else {
            return nil
        }

        let matches = regex.matches(in: fullText, range: NSRange(fullText.startIndex..., in: fullText))
        guard matches.count >= 2 else { return nil }

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
        guard raws.count >= 2 else { return nil }

        // Classify: all digits, or all single letters. Reject mixed.
        let allDigits = raws.allSatisfy { Int($0.marker) != nil }
        let allLetters = raws.allSatisfy { $0.marker.count == 1 && $0.marker.unicodeScalars.first.map { CharacterSet.letters.contains($0) } == true }
        guard allDigits || allLetters else { return nil }

        // Build options with sequential check (1,2,3… or A,B,C…).
        var options: [QuestionOption] = []
        for (i, raw) in raws.enumerated() {
            let expectedIndex = i + 1
            let token: String?
            if allDigits {
                guard let n = Int(raw.marker), n == expectedIndex else { return nil }
                token = nil
            } else {
                let upper = raw.marker.uppercased()
                let scalars = Array(upper.unicodeScalars)
                guard let first = scalars.first,
                      let aScalar = "A".unicodeScalars.first,
                      Int(first.value) - Int(aScalar.value) + 1 == expectedIndex else {
                    return nil
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
        guard options.count >= 2 else { return nil }

        // Reject markdown list items: real CLI options are plain text, while
        // numbered lists in assistant prose typically use **bold** / `code` / *italic*.
        let looksLikeMarkdown = raws.contains { raw in
            raw.label.contains("**") || raw.label.contains("`") || raw.label.hasPrefix("*")
        }
        guard !looksLikeMarkdown else { return nil }

        // Reject overly long labels: CLI options are concise (< ~120 chars).
        let hasLongLabel = raws.contains { $0.label.count > 120 }
        guard !hasLongLabel else { return nil }

        // Last option must end in the final 30% of text.
        guard let lastRange = raws.last?.range,
              lastRange.upperBound > (fullText.utf16.count * 7 / 10) else { return nil }

        // A question mark must appear close to the first option (within ~300 chars),
        // not just anywhere in the preceding prose.
        let firstLocation = raws[0].range.location
        let nsFullText = fullText as NSString
        let windowStart = max(0, firstLocation - 300)
        let preOptions = nsFullText.substring(with: NSRange(location: windowStart, length: firstLocation - windowStart))
        guard preOptions.contains("?") else { return nil }

        return [ParsedQuestion(
            header: "",
            question: "",
            options: options,
            multiSelect: false
        )]
    }

    // MARK: - Current-turn lookups

    /// A transcript's raw JSONL lines, decoded lazily from the end. Transcripts
    /// reach tens of megabytes, and every lookup here asks about the current
    /// turn, so decoding the whole file to answer a question about its last few
    /// lines is wasted work — these run on the hook response path and inside a
    /// SwiftUI body.
    private struct Transcript {
        private let lines: [String]

        init?(path: String) {
            guard !path.isEmpty,
                  let data = FileManager.default.contents(atPath: path),
                  let content = String(data: data, encoding: .utf8) else {
                return nil
            }
            lines = content.components(separatedBy: "\n")
        }

        private static func json(_ line: String) -> [String: Any]? {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData),
                  let json = object as? [String: Any] else {
                return nil
            }
            return json
        }

        /// The newest assistant message of the main conversation — the current
        /// turn — and the line it came from. Sidechain (subagent) messages are
        /// skipped: the panel's card belongs to the main session, so a subagent's
        /// chatter must not stand in for its turn and hide a question the main
        /// agent is waiting on.
        func latestAssistantMessage() -> (line: Int, message: [String: Any])? {
            for index in stride(from: lines.count - 1, through: 0, by: -1) {
                guard let json = Self.json(lines[index]),
                      (json["type"] as? String) == "assistant",
                      (json["isSidechain"] as? Bool) != true,
                      let message = json["message"] as? [String: Any] else {
                    continue
                }
                return (index, message)
            }
            return nil
        }

        /// Whether a `tool_result` for this tool_use id exists — i.e. the user
        /// already answered it, typically in the terminal. Only the lines after
        /// the call are searched: a result can never precede the call it answers.
        func isAnswered(toolUseId: String, askedAt line: Int) -> Bool {
            guard line + 1 < lines.count else { return false }
            for index in (line + 1)..<lines.count {
                guard let json = Self.json(lines[index]),
                      (json["type"] as? String) == "user",
                      let message = json["message"] as? [String: Any],
                      let content = message["content"] as? [[String: Any]] else {
                    continue
                }
                for block in content
                where (block["type"] as? String) == "tool_result"
                    && (block["tool_use_id"] as? String) == toolUseId {
                    return true
                }
            }
            return false
        }
    }

    private static func contentBlocks(in message: [String: Any]) -> [[String: Any]] {
        message["content"] as? [[String: Any]] ?? []
    }

    private static func askUserQuestionBlock(in message: [String: Any]) -> [String: Any]? {
        contentBlocks(in: message).first { block in
            (block["type"] as? String) == "tool_use" && (block["name"] as? String) == "AskUserQuestion"
        }
    }

    /// Text blocks of a message, joined — the shape `parseNumberedOptions` scans.
    private static func allText(in message: [String: Any]) -> String {
        if let contentString = message["content"] as? String { return contentString }
        return contentBlocks(in: message)
            .compactMap { block in
                guard (block["type"] as? String) == "text" else { return nil }
                return block["text"] as? String
            }
            .joined(separator: "\n")
    }

    /// The message's closing prose, trimmed. A question mark here is what marks
    /// a plain-text message as awaiting an answer.
    private static func lastText(in message: [String: Any]) -> String? {
        if let contentString = message["content"] as? String {
            return contentString.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let texts = contentBlocks(in: message).compactMap { block -> String? in
            guard (block["type"] as? String) == "text" else { return nil }
            return block["text"] as? String
        }
        return texts.last?.trimmingCharacters(in: .whitespacesAndNewlines)
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
