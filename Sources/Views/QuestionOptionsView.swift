import SwiftUI

struct QuestionOptionsView: View {
    let questions: [ParsedQuestion]
    /// Returns whether the reply was delivered (see `SendTextField`). Option
    /// buttons ignore the result; the free-text field uses it to keep the
    /// user's text on a failed terminal-paste delivery.
    let onSend: (String) -> Bool
    /// Structured-answer callback for the AskUserQuestion permission hook path.
    /// When set, takes precedence over `onSend` — the answers are returned to
    /// Claude Code via the hook response instead of being typed into the terminal.
    var onAnswers: (([String: String], [String: [String: String]]?) -> Void)? = nil
    /// True when a live Stop-hook hold exists for this session: free text is
    /// delivered as the hook reason in a single message (no option-token +
    /// text two-step, which only exists for the terminal-typing path).
    var hasDirectChannel: Bool = false
    /// Exact tty of the session's terminal, when known (used by the
    /// legacy two-step terminal-paste path).
    var knownTty: String? = nil
    var markerCode: String? = nil
    var iTermSessionId: String? = nil
    var cwd: String = ""
    var transcriptPath: String = ""
    var onDismiss: (() -> Void)?
    @ObservedObject private var bodyStyle = BodyStyleSettings.shared

    @State private var selections: [UUID: Set<Int>] = [:]  // questionId -> selected indices
    @State private var freeTextExpanded = false  // true when "Type something" was clicked

    private static let freeTextPatterns = ["type something", "something else", "other"]

    /// Returns the free-text option for a question, if any.
    private static func freeTextOption(in question: ParsedQuestion) -> QuestionOption? {
        question.options.first { option in
            let lower = option.label.lowercased()
            return freeTextPatterns.contains { lower.contains($0) }
        }
    }

    /// Whether any question has a free-text option.
    private var hasFreeTextOption: Bool {
        questions.contains { Self.freeTextOption(in: $0) != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(questions) { question in
                questionSection(question)
            }

            // Submit button for multi-question or multiSelect
            if questions.count > 1 || questions.contains(where: { $0.multiSelect }) {
                HStack {
                    Spacer()
                    Button("Submit") {
                        submitAll()
                    }
                    .buttonStyle(.orangeProminent)
                    .disabled(!allQuestionsAnswered)
                }
            }

            if freeTextExpanded {
                SendTextField(placeholder: "Type your response...") { text in
                    sendFreeText(text)
                }
            } else if !hasFreeTextOption && questions.count == 1 && !questions.contains(where: { $0.multiSelect }) {
                SendTextField(placeholder: "Or type a custom response...", onSend: onSend)
            }
        }
    }

    private func questionSection(_ question: ParsedQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header + question
            if !question.header.isEmpty {
                Text(question.header)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
                    .textCase(.uppercase)
            }

            MarkdownText(question.question, font: bodyStyle.bodyFont(size: .body), textColor: bodyStyle.fontColor)

            if question.multiSelect {
                Text("Select one or more:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Options
            ForEach(question.options) { option in
                let isFreeText = Self.freeTextOption(in: question)?.id == option.id
                let isSelected = freeTextExpanded && isFreeText
                    ? true
                    : selections[question.id, default: []].contains(option.index)

                if !(freeTextExpanded && isFreeText) {
                    // Show normal option row (hide the free-text option when expanded)
                    optionRow(option: option, isSelected: isSelected, question: question, isFreeText: isFreeText)
                }
            }
        }
    }

    private func optionRow(option: QuestionOption, isSelected: Bool, question: ParsedQuestion, isFreeText: Bool) -> some View {
        HStack(spacing: 8) {
            // Selection indicator
            if question.multiSelect {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? .orange : .secondary)
                    .frame(width: 20)
            } else {
                Text("\(option.token ?? String(option.index)).")
                    .font(.body.monospacedDigit().weight(.semibold))
                    .foregroundStyle(isSelected ? .orange : .secondary)
                    .frame(width: 24, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(option.label)
                        .font(.body.weight(.medium))
                    if isFreeText {
                        Image(systemName: "pencil.line")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !option.description.isEmpty {
                    Text(option.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.orange.opacity(0.12) : Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            if isFreeText {
                // Expand inline text field instead of sending immediately
                withAnimation(.easeInOut(duration: 0.2)) {
                    freeTextExpanded = true
                }
            } else if question.multiSelect {
                // Toggle selection
                freeTextExpanded = false
                var current = selections[question.id, default: []]
                if current.contains(option.index) {
                    current.remove(option.index)
                } else {
                    current.insert(option.index)
                }
                selections[question.id] = current
            } else {
                // Single select → send immediately
                freeTextExpanded = false
                selections[question.id] = [option.index]
                if questions.count == 1 {
                    if let onAnswers {
                        onAnswers([question.question: option.label], nil)
                    } else {
                        _ = onSend(option.token ?? "\(option.index)")
                    }
                }
            }
        }
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() }
            else { NSCursor.pop() }
        }
    }

    private var allQuestionsAnswered: Bool {
        questions.allSatisfy { q in
            !(selections[q.id, default: []].isEmpty)
        }
    }

    private func submitAll() {
        if let onAnswers {
            // Structured path (AskUserQuestion permission hook): map each question
            // to its selected option labels.
            var answers: [String: String] = [:]
            for question in questions {
                let selectedIndices = selections[question.id, default: []].sorted()
                let labels = selectedIndices.compactMap { idx -> String? in
                    question.options.first(where: { $0.index == idx })?.label
                }
                answers[question.question] = labels.joined(separator: ", ")
            }
            onAnswers(answers, nil)
            return
        }

        // Legacy path (transcript-parsed notifications): build "1\n2,3" text to
        // type into the terminal.
        var parts: [String] = []
        for question in questions {
            let selectedIndices = selections[question.id, default: []].sorted()
            let tokens = selectedIndices.compactMap { idx -> String? in
                guard let opt = question.options.first(where: { $0.index == idx }) else { return nil }
                return opt.token ?? String(opt.index)
            }
            parts.append(tokens.joined(separator: ","))
        }
        _ = onSend(parts.joined(separator: "\n"))
    }

    /// Send free-text response. For the structured (hook) path, pass the typed
    /// text directly as the answer for the first question. For the legacy
    /// (terminal-paste) path, use the two-step option-token + text sequence.
    @discardableResult
    private func sendFreeText(_ text: String) -> Bool {
        if let onAnswers, let firstQuestion = questions.first {
            onAnswers([firstQuestion.question: text], nil)
            return true
        }
        if hasDirectChannel {
            return onSend(text)
        }
        if let firstQuestion = questions.first,
           let option = Self.freeTextOption(in: firstQuestion),
           !cwd.isEmpty {
            let markerStr = markerCode.map { TerminalBridge.markerString(code: $0) }
            let sent = TerminalBridge.sendTextTwoStep(option.token ?? "\(option.index)", then: text, toCwd: cwd, transcriptPath: transcriptPath, knownTty: knownTty, marker: markerStr, iTermSessionId: iTermSessionId)
            // Only tear down the card once the text actually reached the tab;
            // otherwise keep it open so the field can report the failure.
            if sent { onDismiss?() }
            return sent
        }
        return onSend(text)
    }
}
