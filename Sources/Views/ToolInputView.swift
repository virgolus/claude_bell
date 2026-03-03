import SwiftUI

struct ToolInputView: View {
    let toolInput: [String: AnyCodable]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tool Input")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(toolInput.keys.sorted()), id: \.self) { key in
                VStack(alignment: .leading, spacing: 2) {
                    Text(key)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    let value = toolInput[key]?.description ?? "—"
                    if looksLikeCode(key: key, value: value) {
                        ScrollView {
                            Text(value)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                        .frame(maxHeight: 300)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        ScrollView {
                            MarkdownText(value)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 400)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
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
