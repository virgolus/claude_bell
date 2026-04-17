import SwiftUI
import AppKit

enum ActionButton {
    case allow
    case allowAlways
    case deny

    var behavior: PermissionBehavior {
        switch self {
        case .allow: return .allow
        case .allowAlways: return .allowAlways
        case .deny: return .deny
        }
    }
}

struct RequestDetailView: View {
    @EnvironmentObject var store: RequestStore
    let request: PendingRequest
    @State private var remainingSeconds: Int = 300
    @State private var focused: ActionButton? = .allow
    @State private var footerFocused: DetailFooterView.FooterButton?
    @State private var keyMonitor: Any?
    @State private var cachedQuestions: [ParsedQuestion]?

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Whether focus is on the footer row
    private var isInFooter: Bool { footerFocused != nil }

    private var isAskUserQuestion: Bool { request.toolName == "AskUserQuestion" }
    private var isExitPlanMode: Bool { request.toolName == "ExitPlanMode" }
    private var isSpecialTool: Bool { isAskUserQuestion || isExitPlanMode }

    private var canAlwaysAllow: Bool {
        if let suggestions = request.permissionSuggestions, !suggestions.isEmpty {
            return true
        }
        return false
    }

    /// Parse questions from toolInput["questions"] — called once in onAppear
    private static func parseQuestions(from toolInput: [String: AnyCodable]) -> [ParsedQuestion]? {
        guard let questionsAnyCodable = toolInput["questions"],
              let questionsArray = questionsAnyCodable.value as? [Any] else {
            return nil
        }

        var parsed: [ParsedQuestion] = []
        for item in questionsArray {
            guard let q = item as? [String: Any],
                  let questionText = q["question"] as? String else { continue }
            let header = q["header"] as? String ?? ""
            let multiSelect = q["multiSelect"] as? Bool ?? false
            var options: [QuestionOption] = []

            if let opts = q["options"] as? [Any] {
                for (i, optItem) in opts.enumerated() {
                    if let opt = optItem as? [String: Any] {
                        options.append(QuestionOption(
                            index: i + 1,
                            label: opt["label"] as? String ?? "Option \(i + 1)",
                            description: opt["description"] as? String ?? "",
                            token: nil
                        ))
                    }
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

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: ToolIconMapper.icon(for: request.toolName))
                            .font(.title2)
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            RenameableTitleView(text: request.projectName, sessionId: request.sessionId)
                            Text(isAskUserQuestion ? "Question" : isExitPlanMode ? "Plan Review" : request.toolName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let lastPrompt = store.sessions[request.sessionId]?.lastPrompt {
                                Text(lastPrompt)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        Text(formatCountdown(remainingSeconds))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(remainingSeconds < 60 ? .red : .secondary)
                    }

                    Divider()

                    if let questions = cachedQuestions {
                        // AskUserQuestion: show interactive question options
                        QuestionOptionsView(
                            questions: questions,
                            onSend: { text in
                                request.respond(.allow)
                                store.removeRequest(id: request.id)
                                // Delay typing until Claude Code has rendered the prompt
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    TerminalBridge.sendText(text, toCwd: request.cwd, transcriptPath: request.transcriptPath)
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    NSApplication.shared.activate()
                                }
                            },
                            cwd: request.cwd,
                            transcriptPath: request.transcriptPath,
                            onDismiss: {
                                request.respond(.allow)
                                store.removeRequest(id: request.id)
                            }
                        )
                    } else if isExitPlanMode {
                        // ExitPlanMode: show plan as markdown + action options
                        ExitPlanModeView(request: request, store: store)
                    } else {
                        // Normal permission request
                        Text(permissionDescription)
                            .font(.callout)
                            .foregroundStyle(.primary)

                        ToolInputView(toolInput: request.toolInput)
                    }

                    if !request.transcriptPath.isEmpty {
                        Divider()
                        ConversationContextView(transcriptPath: request.transcriptPath)
                    }
                }
                .padding()
            }

            if !isSpecialTool {
                Divider()

                HStack(spacing: 10) {
                    actionButton(label: "Deny", icon: "xmark.circle", action: .deny, color: .red)
                    actionButton(label: "Allow", icon: "checkmark.circle", action: .allow, color: .orange)
                    if canAlwaysAllow {
                        actionButton(label: "Always", icon: "checkmark.circle.fill", action: .allowAlways, color: .green)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 4)
            }

            DetailFooterView(cwd: request.cwd, transcriptPath: request.transcriptPath, standalone: false, focusedButton: footerFocused, onOpenInTerminal: {
                TerminalBridge.focusTerminalTab(forCwd: request.cwd, transcriptPath: request.transcriptPath)
                request.respond(allow: false)
                store.removeRequest(id: request.id)
            }) {
                request.respond(allow: false)
                store.removeRequest(id: request.id)
            }
        }
        .onReceive(timer) { _ in
            let elapsed = Int(-request.createdAt.timeIntervalSinceNow)
            remainingSeconds = max(0, 300 - elapsed)
        }
        .onAppear {
            let elapsed = Int(-request.createdAt.timeIntervalSinceNow)
            remainingSeconds = max(0, 300 - elapsed)
            focused = isSpecialTool ? nil : (canAlwaysAllow ? .allowAlways : .allow)
            footerFocused = nil
            if isAskUserQuestion {
                cachedQuestions = Self.parseQuestions(from: request.toolInput)
            }
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    private func actionButton(label: String, icon: String, action: ActionButton, color: Color) -> some View {
        let isFocused = focused == action && !isInFooter
        return HStack(spacing: 6) {
            Image(systemName: icon)
            Text(label)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isFocused ? color.opacity(0.2) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isFocused ? color : Color.secondary.opacity(0.3), lineWidth: isFocused ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            focused = action
            footerFocused = nil
            confirm()
        }
    }

    private func confirm() {
        guard let action = focused, !isInFooter else { return }
        request.respond(action.behavior)
        store.removeRequest(id: request.id)
    }

    private var buttonOrder: [ActionButton] {
        canAlwaysAllow ? [.deny, .allow, .allowAlways] : [.deny, .allow]
    }
    private static let footerOrder: [DetailFooterView.FooterButton] = [.dismiss, .openInTerminal]

    private func installKeyMonitor() {
        let buttons = buttonOrder
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Don't intercept keys when a text field is active (e.g. renaming a session)
            if isTextFieldActive() { return event }
            switch event.keyCode {
            case 123: // left arrow
                if isInFooter {
                    footerFocused = .dismiss
                } else if let current = focused, let idx = buttons.firstIndex(of: current), idx > 0 {
                    focused = buttons[idx - 1]
                }
                return nil
            case 124: // right arrow
                if isInFooter {
                    footerFocused = .openInTerminal
                } else if let current = focused, let idx = buttons.firstIndex(of: current), idx < buttons.count - 1 {
                    focused = buttons[idx + 1]
                }
                return nil
            case 125: // down arrow
                if !isInFooter {
                    footerFocused = .dismiss
                    focused = nil
                }
                return nil
            case 126: // up arrow
                if isInFooter {
                    footerFocused = nil
                    focused = .allow
                }
                return nil
            case 36: // return
                if isInFooter {
                    activateFooter()
                } else {
                    confirm()
                }
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func activateFooter() {
        switch footerFocused {
        case .dismiss:
            request.respond(allow: false)
            store.removeRequest(id: request.id)
        case .openInTerminal:
            TerminalBridge.focusTerminalTab(forCwd: request.cwd, transcriptPath: request.transcriptPath)
            request.respond(allow: false)
            store.removeRequest(id: request.id)
        case nil:
            break
        }
    }

    private var permissionDescription: String {
        switch request.toolName {
        case "Bash":
            return "Claude wants to run a shell command:"
        case "Write":
            return "Claude wants to create or overwrite a file:"
        case "Edit":
            return "Claude wants to edit a file:"
        case "Read":
            return "Claude wants to read a file:"
        case "WebFetch":
            return "Claude wants to fetch a URL:"
        case "WebSearch":
            return "Claude wants to search the web:"
        case "NotebookEdit":
            return "Claude wants to edit a notebook:"
        default:
            return "Claude wants to use \(request.toolName):"
        }
    }

    private func formatCountdown(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
