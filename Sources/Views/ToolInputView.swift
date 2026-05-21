import SwiftUI

struct ToolInputView: View {
    let toolInput: [String: AnyCodable]
    @ObservedObject private var bodyStyle = BodyStyleSettings.shared

    private var isEditDiff: Bool {
        toolInput["old_string"] != nil && toolInput["new_string"] != nil
    }

    private var diffKeys: Set<String> { ["old_string", "new_string"] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tool Input")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            let keys = toolInput.keys.sorted().filter { !(isEditDiff && diffKeys.contains($0)) }
            ForEach(keys, id: \.self) { key in
                fieldView(for: key)
            }

            if isEditDiff {
                diffView
            }
        }
    }

    @ViewBuilder
    private func fieldView(for key: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            let value = toolInput[key]?.description ?? "—"
            if looksLikeCode(key: key, value: value) {
                ScrollView {
                    Text(value)
                        .font(bodyStyle.fontName != nil ? bodyStyle.bodyFont(size: .body) : .system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 300)
                .background(bodyStyle.backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                ScrollView {
                    MarkdownText(value, font: bodyStyle.bodyFont(size: .body), textColor: bodyStyle.fontColor)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 400)
                .background(bodyStyle.backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var diffView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("diff")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            let oldString = toolInput["old_string"]?.description ?? ""
            let newString = toolInput["new_string"]?.description ?? ""
            let lines = DiffComputer.compute(old: oldString, new: newString)
            let font: Font = bodyStyle.fontName != nil ? bodyStyle.bodyFont(size: .body) : .system(.body, design: .monospaced)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { line in
                        HStack(alignment: .top, spacing: 6) {
                            Text(line.kind.marker)
                                .font(font)
                                .foregroundStyle(line.kind.foreground)
                                .frame(width: 12, alignment: .leading)
                            Text(line.text.isEmpty ? " " : line.text)
                                .font(font)
                                .foregroundStyle(line.kind.foreground)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1)
                        .background(line.kind.background)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 400)
            .background(bodyStyle.backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func looksLikeCode(key: String, value: String) -> Bool {
        let codeKeys = ["command", "new_source", "old_string", "new_string", "file_path"]
        if codeKeys.contains(key) { return true }
        // "content" is code unless the file being written is markdown
        if key == "content" {
            let filePath = toolInput["file_path"]?.description ?? ""
            return !filePath.hasSuffix(".md")
        }
        // Markdown keys should be rendered as markdown, not code
        let markdownKeys = ["plan", "description", "prompt", "message", "text", "body"]
        if markdownKeys.contains(key) { return false }
        // Heuristic: if it has markdown headings, render as markdown
        if value.contains("\n# ") || value.contains("\n## ") || value.contains("\n- ") || value.starts(with: "# ") {
            return false
        }
        return false
    }
}

// MARK: - Diff

struct DiffLine: Identifiable {
    enum Kind {
        case context, removed, added

        var marker: String {
            switch self {
            case .context: return " "
            case .removed: return "−"
            case .added:   return "+"
            }
        }

        var foreground: Color {
            switch self {
            case .context: return .primary
            case .removed: return Color(red: 0.85, green: 0.25, blue: 0.25)
            case .added:   return Color(red: 0.20, green: 0.65, blue: 0.30)
            }
        }

        var background: Color {
            switch self {
            case .context: return .clear
            case .removed: return Color.red.opacity(0.15)
            case .added:   return Color.green.opacity(0.15)
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let text: String
}

enum DiffComputer {
    /// Line-by-line diff using LCS. Common lines are shown as context; the rest
    /// are emitted as removed (from `old`) or added (from `new`).
    static func compute(old: String, new: String) -> [DiffLine] {
        let oldLines = old.components(separatedBy: "\n")
        let newLines = new.components(separatedBy: "\n")
        let m = oldLines.count
        let n = newLines.count

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 0..<m {
            for j in 0..<n {
                if oldLines[i] == newLines[j] {
                    dp[i + 1][j + 1] = dp[i][j] + 1
                } else {
                    dp[i + 1][j + 1] = max(dp[i + 1][j], dp[i][j + 1])
                }
            }
        }

        var result: [DiffLine] = []
        var i = m, j = n
        while i > 0 && j > 0 {
            if oldLines[i - 1] == newLines[j - 1] {
                result.append(DiffLine(kind: .context, text: oldLines[i - 1]))
                i -= 1; j -= 1
            } else if dp[i - 1][j] >= dp[i][j - 1] {
                result.append(DiffLine(kind: .removed, text: oldLines[i - 1]))
                i -= 1
            } else {
                result.append(DiffLine(kind: .added, text: newLines[j - 1]))
                j -= 1
            }
        }
        while i > 0 { result.append(DiffLine(kind: .removed, text: oldLines[i - 1])); i -= 1 }
        while j > 0 { result.append(DiffLine(kind: .added, text: newLines[j - 1])); j -= 1 }

        return result.reversed()
    }
}
