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
                        MarkdownText(value)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }

    private func looksLikeCode(key: String, value: String) -> Bool {
        let codeKeys = ["command", "content", "new_source", "old_string", "new_string", "file_path"]
        return codeKeys.contains(key) || value.contains("\n")
    }
}
