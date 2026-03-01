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

                    Text(toolInput[key]?.description ?? "—")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }
}
