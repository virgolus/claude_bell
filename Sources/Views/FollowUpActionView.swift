import SwiftUI

struct FollowUpActionView: View {
    let notification: NotificationEntry
    let onSend: (String) -> Void

    enum Mode {
        case none, prompt, contract
    }

    enum ContractField: Hashable {
        case title, goal, constraints, format, failure
    }

    @State private var mode: Mode = .none
    @State private var promptText = ""
    @FocusState private var promptFocused: Bool
    @FocusState private var contractFocus: ContractField?

    // Contract fields
    @State private var contractTitle = ""
    @State private var contractGoal = ""
    @State private var contractConstraints = ""
    @State private var contractFormat = ""
    @State private var contractFailure = ""

    var body: some View {
        switch mode {
        case .none:
            HStack {
                Menu {
                    Button("Prompt") {
                        mode = .prompt
                        promptFocused = true
                    }
                    Button("Contract") {
                        mode = .contract
                        contractFocus = .title
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer()
            }

        case .prompt:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Follow-up Prompt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        mode = .none
                        promptText = ""
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 8) {
                    TextField("Type your follow-up...", text: $promptText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...5)
                        .focused($promptFocused)
                        .onSubmit { sendPrompt() }

                    Button("Send") { sendPrompt() }
                        .keyboardShortcut(.return, modifiers: .command)
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .disabled(promptText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

        case .contract:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Follow-up Contract")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        mode = .none
                        clearContract()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }

                contractField("TITLE", text: $contractTitle, focus: .title)
                contractField("GOAL", text: $contractGoal, focus: .goal, axis: .vertical)
                contractField("CONSTRAINTS", text: $contractConstraints, focus: .constraints, axis: .vertical)
                contractField("FORMAT", text: $contractFormat, focus: .format, axis: .vertical)
                contractField("FAILURE CONDITIONS", text: $contractFailure, focus: .failure, axis: .vertical)

                Button("Send Contract") { sendContract() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(contractGoal.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    @ViewBuilder
    private func contractField(_ label: String, text: Binding<String>, focus: ContractField, axis: Axis = .horizontal) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField(label.capitalized, text: text, axis: axis == .vertical ? .vertical : .horizontal)
                .textFieldStyle(.roundedBorder)
                .lineLimit(axis == .vertical ? 1...4 : 1...1)
                .focused($contractFocus, equals: focus)
                .onSubmit { advanceContractFocus(from: focus) }
        }
    }

    private func advanceContractFocus(from current: ContractField) {
        switch current {
        case .title: contractFocus = .goal
        case .goal: contractFocus = .constraints
        case .constraints: contractFocus = .format
        case .format: contractFocus = .failure
        case .failure: sendContract()
        }
    }

    private func sendPrompt() {
        let text = promptText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        onSend(text)
        promptText = ""
    }

    private func sendContract() {
        let title = contractTitle.trimmingCharacters(in: .whitespaces)
        let goal = contractGoal.trimmingCharacters(in: .whitespaces)
        let constraints = contractConstraints.trimmingCharacters(in: .whitespaces)
        let format = contractFormat.trimmingCharacters(in: .whitespaces)
        let failure = contractFailure.trimmingCharacters(in: .whitespaces)

        guard !goal.isEmpty else { return }

        var parts: [String] = []
        if !title.isEmpty { parts.append("# \(title)") }
        if !goal.isEmpty { parts.append("## GOAL\n\(goal)") }
        if !constraints.isEmpty { parts.append("## CONSTRAINTS\n\(constraints)") }
        if !format.isEmpty { parts.append("## FORMAT\n\(format)") }
        if !failure.isEmpty { parts.append("## FAILURE CONDITIONS\n\(failure)") }

        onSend(parts.joined(separator: "\n\n"))
        clearContract()
    }

    private func clearContract() {
        contractTitle = ""
        contractGoal = ""
        contractConstraints = ""
        contractFormat = ""
        contractFailure = ""
    }
}
