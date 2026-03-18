import SwiftUI

struct QuestionOptionsView: View {
    let questions: [ParsedQuestion]
    let onSend: (String) -> Void
    var cwd: String = ""
    var onDismiss: (() -> Void)?
    @ObservedObject private var bodyStyle = BodyStyleSettings.shared

    @State private var selections: [UUID: Set<Int>] = [:]  // questionId -> selected indices
    @State private var customText = ""
    @State private var freeTextExpanded = false  // true when "Type something" was clicked
    @FocusState private var freeTextFocused: Bool

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
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(!allQuestionsAnswered)
                }
            }

            if freeTextExpanded {
                // Inline text field shown after clicking "Type something"
                HStack(spacing: 8) {
                    TextField("Type your response...", text: $customText)
                        .textFieldStyle(.roundedBorder)
                        .focused($freeTextFocused)
                        .onSubmit { sendFreeText() }

                    Button("Send") { sendFreeText() }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(customText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else if !hasFreeTextOption && questions.count == 1 && !questions.contains(where: { $0.multiSelect }) {
                // Free text fallback only for single-select without a "Type something" option
                HStack(spacing: 8) {
                    TextField("Or type a custom response...", text: $customText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { sendCustom() }

                    Button("Send") { sendCustom() }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(customText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
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
                Text("\(option.index).")
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    freeTextFocused = true
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
                    onSend("\(option.index)")
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
        // Build response: for each question, send the selected option numbers
        // Format: "1\n2,3" (one line per question, comma-separated for multiSelect)
        var parts: [String] = []
        for question in questions {
            let selected = selections[question.id, default: []].sorted()
            parts.append(selected.map(String.init).joined(separator: ","))
        }
        onSend(parts.joined(separator: "\n"))
    }

    /// Send free-text response via two-step (option number + custom text).
    private func sendFreeText() {
        let text = customText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        if let firstQuestion = questions.first,
           let option = Self.freeTextOption(in: firstQuestion),
           !cwd.isEmpty {
            TerminalBridge.sendTextTwoStep("\(option.index)", then: text, toCwd: cwd)
            onDismiss?()
        } else {
            onSend(text)
        }
    }

    /// Fallback custom text send (when no free-text option exists).
    private func sendCustom() {
        let text = customText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        onSend(text)
    }
}
