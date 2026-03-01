import SwiftUI

/// A view that renders markdown text with proper formatting.
struct MarkdownText: View {
    let content: String
    let font: Font

    init(_ content: String, font: Font = .body) {
        self.content = content
        self.font = font
    }

    var body: some View {
        if content.contains("```") {
            // Has code blocks — split and render separately
            codeBlockRendering
        } else {
            // Simple markdown — use native AttributedString
            simpleMarkdown
                .textSelection(.enabled)
        }
    }

    private var simpleMarkdown: Text {
        if let attributed = try? AttributedString(markdown: content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed).font(font)
        } else {
            return Text(content).font(font)
        }
    }

    private var codeBlockRendering: some View {
        let blocks = parseCodeBlocks(content)
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                if block.isCode {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(block.content)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(10)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                } else if !block.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if let attributed = try? AttributedString(markdown: block.content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                        Text(attributed)
                            .font(font)
                            .textSelection(.enabled)
                    } else {
                        Text(block.content)
                            .font(font)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private struct ContentBlock {
        let content: String
        let isCode: Bool
    }

    private func parseCodeBlocks(_ text: String) -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        var remaining = text
        while let start = remaining.range(of: "```") {
            // Text before code block
            let before = String(remaining[remaining.startIndex..<start.lowerBound])
            if !before.isEmpty {
                blocks.append(ContentBlock(content: before, isCode: false))
            }
            remaining = String(remaining[start.upperBound...])
            // Skip optional language identifier on the same line
            if let newline = remaining.firstIndex(of: "\n") {
                remaining = String(remaining[remaining.index(after: newline)...])
            }
            // Find closing ```
            if let end = remaining.range(of: "```") {
                let code = String(remaining[remaining.startIndex..<end.lowerBound])
                blocks.append(ContentBlock(content: code.trimmingCharacters(in: .newlines), isCode: true))
                remaining = String(remaining[end.upperBound...])
            } else {
                // No closing — treat rest as code
                blocks.append(ContentBlock(content: remaining.trimmingCharacters(in: .newlines), isCode: true))
                remaining = ""
            }
        }
        if !remaining.isEmpty {
            blocks.append(ContentBlock(content: remaining, isCode: false))
        }
        return blocks
    }
}
