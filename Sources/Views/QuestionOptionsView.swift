import SwiftUI

struct QuestionOptionsView: View {
    let questions: [ParsedQuestion]
    let onSend: (String) -> Void

    @State private var selections: [UUID: Set<Int>] = [:]  // questionId -> selected indices
    @State private var customText = ""

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

            // Free text fallback
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

    private func questionSection(_ question: ParsedQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header + question
            if !question.header.isEmpty {
                Text(question.header)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
                    .textCase(.uppercase)
            }

            MarkdownText(question.question, font: .body)

            if question.multiSelect {
                Text("Select one or more:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Options
            ForEach(question.options) { option in
                let isSelected = selections[question.id, default: []].contains(option.index)
                optionRow(option: option, isSelected: isSelected, question: question)
            }
        }
    }

    private func optionRow(option: QuestionOption, isSelected: Bool, question: ParsedQuestion) -> some View {
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
                Text(option.label)
                    .font(.body.weight(.medium))
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
            if question.multiSelect {
                // Toggle selection
                var current = selections[question.id, default: []]
                if current.contains(option.index) {
                    current.remove(option.index)
                } else {
                    current.insert(option.index)
                }
                selections[question.id] = current
            } else {
                // Single select
                selections[question.id] = [option.index]
                // If single question, single select → send immediately
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

    private func sendCustom() {
        let text = customText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        onSend(text)
    }
}
