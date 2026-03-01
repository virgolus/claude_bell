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
        if content.contains("```") || containsTable(content) {
            // Has code blocks or tables — split and render separately
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
                    if block.isTable {
                        tableView(block.content)
                    } else if let attributed = try? AttributedString(markdown: block.content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
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
        var isTable: Bool = false
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
            // Split remaining text to separate table blocks from regular text
            blocks.append(contentsOf: splitTables(remaining))
        }
        return blocks
    }

    /// Detect if text contains a markdown table (lines starting with |)
    private func containsTable(_ text: String) -> Bool {
        let lines = text.components(separatedBy: "\n")
        var pipeLineCount = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                pipeLineCount += 1
                if pipeLineCount >= 2 { return true }
            } else {
                pipeLineCount = 0
            }
        }
        return false
    }

    /// Split text into table and non-table blocks
    private func splitTables(_ text: String) -> [ContentBlock] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [ContentBlock] = []
        var currentLines: [String] = []
        var inTable = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isTableLine = trimmed.hasPrefix("|") && trimmed.hasSuffix("|")

            if isTableLine && !inTable {
                // Flush non-table text
                if !currentLines.isEmpty {
                    let content = currentLines.joined(separator: "\n")
                    if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        blocks.append(ContentBlock(content: content, isCode: false))
                    }
                    currentLines = []
                }
                inTable = true
                currentLines.append(line)
            } else if isTableLine && inTable {
                currentLines.append(line)
            } else if !isTableLine && inTable {
                // Flush table
                let content = currentLines.joined(separator: "\n")
                blocks.append(ContentBlock(content: content, isCode: false, isTable: true))
                currentLines = [line]
                inTable = false
            } else {
                currentLines.append(line)
            }
        }

        if !currentLines.isEmpty {
            let content = currentLines.joined(separator: "\n")
            if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(ContentBlock(content: content, isCode: false, isTable: inTable))
            }
        }

        return blocks
    }

    /// Render a markdown table as a formatted grid
    private func tableView(_ text: String) -> some View {
        let rows = parseTable(text)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                if row.isSeparator {
                    Divider()
                } else {
                    HStack(spacing: 0) {
                        ForEach(Array(row.cells.enumerated()), id: \.offset) { colIdx, cell in
                            Text(cell.trimmingCharacters(in: .whitespaces))
                                .font(rowIdx == 0 ? font.weight(.semibold) : font)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                            if colIdx < row.cells.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .background(rowIdx == 0 ? Color.secondary.opacity(0.08) : Color.clear)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private struct TableRow {
        let cells: [String]
        let isSeparator: Bool
    }

    private func parseTable(_ text: String) -> [TableRow] {
        text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Check if separator row (|---|---|)
                let inner = String(trimmed.dropFirst().dropLast())
                let isSep = inner.allSatisfy { $0 == "-" || $0 == "|" || $0 == ":" || $0 == " " }
                    && inner.contains("-")
                let cells = inner.components(separatedBy: "|")
                return TableRow(cells: cells, isSeparator: isSep)
            }
    }
}
