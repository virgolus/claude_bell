import Foundation

// Regression checks for TranscriptParser. Compiled together with the real
// Sources/Transcript/TranscriptParser.swift by run.sh — no XCTest needed, so
// this runs on a machine with only the Command Line Tools installed.
//
// What is being guarded: the panel renders answer options parsed out of the
// session transcript, and those options must always belong to the *current*
// turn. A question surfaced from an earlier point in the conversation is one
// the user already answered, so re-proposing it makes the panel ask a stale
// question.

var failures = 0
var checks = 0

func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if condition {
        print("  ok   \(name)")
    } else {
        failures += 1
        let extra = detail()
        print("  FAIL \(name)\(extra.isEmpty ? "" : " — \(extra)")")
    }
}

// MARK: - Fixture helpers

var temporaryFiles: [URL] = []

func writeTranscript(_ lines: [[String: Any]]) -> String {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("transcript-\(UUID().uuidString).jsonl")
    let jsonl = lines.map { line -> String in
        let data = try! JSONSerialization.data(withJSONObject: line)
        return String(data: data, encoding: .utf8)!
    }.joined(separator: "\n")
    try! jsonl.write(to: url, atomically: true, encoding: .utf8)
    temporaryFiles.append(url)
    return url.path
}

func askUserQuestion(id: String, question: String) -> [String: Any] {
    [
        "type": "assistant",
        "message": [
            "role": "assistant",
            "content": [[
                "type": "tool_use",
                "id": id,
                "name": "AskUserQuestion",
                "input": ["questions": [[
                    "question": question,
                    "header": "Scope",
                    "multiSelect": false,
                    "options": [
                        ["label": "Yes", "description": "do it"],
                        ["label": "No", "description": "skip it"],
                    ],
                ]]],
            ]],
        ],
    ]
}

func toolResult(id: String, text: String = "Yes") -> [String: Any] {
    [
        "type": "user",
        "message": [
            "role": "user",
            "content": [["type": "tool_result", "tool_use_id": id, "content": text]],
        ],
    ]
}

func assistantText(_ text: String) -> [String: Any] {
    ["type": "assistant", "message": ["role": "assistant", "content": [["type": "text", "text": text]]]]
}

func userText(_ text: String) -> [String: Any] {
    ["type": "user", "message": ["role": "user", "content": [["type": "text", "text": text]]]]
}

// MARK: - parseLastQuestions

print("parseLastQuestions")

// The reported bug: an AskUserQuestion answered many turns ago must not be
// resurrected just because the latest assistant message happens to end in a
// question mark (which is what promotes the card to interactive).
do {
    let path = writeTranscript([
        userText("start"),
        askUserQuestion(id: "toolu_old", question: "Old question already answered?"),
        toolResult(id: "toolu_old"),
        assistantText("Done with that."),
        userText("now do something else"),
        assistantText("Finished. Want me to also update the docs?"),
    ])
    let parsed = TranscriptParser.parseLastQuestions(from: path)
    check("a question from an earlier turn is not re-proposed", parsed == nil,
          "got: \(parsed?.first?.question ?? "nil")")
}

// A genuinely pending AskUserQuestion in the newest assistant message is
// exactly what the panel should render.
do {
    let path = writeTranscript([
        userText("start"),
        askUserQuestion(id: "toolu_current", question: "Which approach?"),
    ])
    let parsed = TranscriptParser.parseLastQuestions(from: path)
    check("a pending question in the latest assistant message is parsed",
          parsed?.count == 1 && parsed?.first?.question == "Which approach?"
              && parsed?.first?.options.map(\.label) == ["Yes", "No"],
          "got: \(String(describing: parsed?.first?.question))")
}

// The question is still the newest assistant message, but a tool_result shows
// the user already answered it in the terminal.
do {
    let path = writeTranscript([
        userText("start"),
        askUserQuestion(id: "toolu_answered", question: "Which approach?"),
        toolResult(id: "toolu_answered"),
    ])
    let parsed = TranscriptParser.parseLastQuestions(from: path)
    check("a question already answered in the terminal is not re-proposed", parsed == nil,
          "got: \(parsed?.first?.question ?? "nil")")
}

// Sidechain (subagent) traffic must not shadow the main agent's pending question.
do {
    var sidechain = assistantText("Subagent finished scanning.")
    sidechain["isSidechain"] = true
    let path = writeTranscript([
        userText("start"),
        askUserQuestion(id: "toolu_main", question: "Main agent question?"),
        sidechain,
    ])
    let parsed = TranscriptParser.parseLastQuestions(from: path)
    check("sidechain messages do not shadow the pending question",
          parsed?.first?.question == "Main agent question?",
          "got: \(parsed?.first?.question ?? "nil")")
}

// MARK: - parseNumberedOptions

print("parseNumberedOptions")

// Same class of bug for the text-scraped options path.
do {
    let path = writeTranscript([
        userText("start"),
        assistantText("How should I proceed?\n1. Rewrite it\n2. Patch it\n3. Leave it"),
        userText("2"),
        assistantText("Patched it. Everything builds now."),
    ])
    let parsed = TranscriptParser.parseNumberedOptions(from: path)
    check("enumerated options from an earlier turn are not re-proposed", parsed == nil,
          "got: \(String(describing: parsed?.first?.options.map(\.label)))")
}

do {
    let path = writeTranscript([
        userText("start"),
        assistantText("How should I proceed?\n1. Rewrite it\n2. Patch it\n3. Leave it"),
    ])
    let parsed = TranscriptParser.parseNumberedOptions(from: path)
    check("enumerated options in the latest assistant message are parsed",
          parsed?.first?.options.map(\.label) == ["Rewrite it", "Patch it", "Leave it"],
          "got: \(String(describing: parsed?.first?.options.map(\.label)))")
}

for url in temporaryFiles { try? FileManager.default.removeItem(at: url) }

print("\n\(checks - failures)/\(checks) checks passed")
exit(failures == 0 ? 0 : 1)
