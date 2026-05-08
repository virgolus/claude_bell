import SwiftUI

/// A view that renders markdown text with proper formatting including headings, lists, code blocks, and tables.
struct MarkdownText: View {
    @ObservedObject private var bodyStyle = BodyStyleSettings.shared
    let content: String
    let font: Font
    let textColor: Color?

    init(_ content: String, font: Font = .body, textColor: Color? = nil) {
        self.content = content
        self.font = font
        self.textColor = textColor
    }

    /// Font for inline / block code. Honours the user's chosen body font when set,
    /// otherwise falls back to the system monospaced font at the requested size.
    private func codeFont(size: Font.TextStyle) -> Font {
        if bodyStyle.fontName != nil {
            return bodyStyle.bodyFont(size: size)
        }
        return .system(size, design: .monospaced)
    }

    /// Font for headings — same family as the user's chosen body font (or system),
    /// scaled to the heading's text style.
    private func headingBaseFont(size: Font.TextStyle) -> Font {
        if bodyStyle.fontName != nil {
            return bodyStyle.bodyFont(size: size)
        }
        return .system(size)
    }

    var body: some View {
        let blocks = parseAllBlocks(content)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    // MARK: - Block types

    private enum Block {
        case heading(level: Int, text: String)
        case codeBlock(String)
        case table(String)
        case listItem(indent: Int, ordered: Bool, number: Int?, text: String)
        case paragraph(String)
        case divider
    }

    // MARK: - Rendering

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            headingView(level: level, text: text)
        case .codeBlock(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(codeFont(size: .caption))
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
        case .table(let tableText):
            tableView(tableText)
        case .listItem(let indent, _, _, let text):
            HStack(alignment: .top, spacing: 4) {
                Text("•")
                    .font(font)
                    .foregroundStyle(.secondary)
                inlineMarkdown(text)
            }
            .padding(.leading, CGFloat(indent) * 16)
        case .paragraph(let text):
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                inlineMarkdown(text)
            }
        case .divider:
            Divider()
        }
    }

    private func headingView(level: Int, text: String) -> some View {
        let style: Font.TextStyle = switch level {
        case 1: .title
        case 2: .title2
        case 3: .title3
        default: .headline
        }
        let weight: Font.Weight = level <= 2 ? .bold : .semibold
        let headingFont = headingBaseFont(size: style).weight(weight)
        return inlineMarkdown(text, font: headingFont)
            .padding(.top, level <= 2 ? 4 : 2)
    }

    @ViewBuilder
    private func inlineMarkdown(_ text: String, font overrideFont: Font? = nil) -> some View {
        let f = overrideFont ?? font
        let spans = parseInlineSpans(text)
        // NOTE: apply `.font(f)` to every span explicitly. Applying `.font` as a
        // View modifier to a concatenated `Text` does NOT reliably propagate to
        // children, so plain/bold/italic spans were silently picking up the
        // ambient system font instead of the user's chosen body font.
        let rendered = spans.reduce(Text("")) { result, span in
            switch span {
            case .plain(let s):
                return result + Text(s).font(f)
            case .bold(let s):
                return result + Text(s).font(f).bold()
            case .italic(let s):
                return result + Text(s).font(f).italic()
            case .boldItalic(let s):
                return result + Text(s).font(f).bold().italic()
            case .code(let s):
                return result + Text(s).font(codeFont(size: .body)).foregroundColor(.accentColor)
            case .boldCode(let s):
                return result + Text(s).font(codeFont(size: .body)).bold().foregroundColor(.accentColor)
            }
        }
        if let textColor {
            rendered.foregroundStyle(textColor).textSelection(.enabled)
        } else {
            rendered.textSelection(.enabled)
        }
    }

    // MARK: - Inline span parsing

    private enum InlineSpan {
        case plain(String)
        case bold(String)
        case italic(String)
        case boldItalic(String)
        case code(String)
        case boldCode(String)
    }

    /// Parse inline markdown into spans: **bold**, *italic*, ***boldItalic***, `code`, **`boldCode`**
    private func parseInlineSpans(_ text: String) -> [InlineSpan] {
        var spans: [InlineSpan] = []
        var remaining = text[text.startIndex...]

        while !remaining.isEmpty {
            // Find the next special character
            guard let specialIdx = remaining.firstIndex(where: { $0 == "*" || $0 == "`" }) else {
                spans.append(.plain(String(remaining)))
                break
            }

            // Add plain text before the special char
            if specialIdx > remaining.startIndex {
                spans.append(.plain(String(remaining[remaining.startIndex..<specialIdx])))
                remaining = remaining[specialIdx...]
            }

            if remaining.hasPrefix("```") {
                // Skip triple backticks (code blocks handled at block level)
                spans.append(.plain("```"))
                remaining = remaining[remaining.index(remaining.startIndex, offsetBy: 3)...]
            } else if remaining.hasPrefix("`") {
                // Inline code
                let afterTick = remaining.index(after: remaining.startIndex)
                if let endTick = remaining[afterTick...].firstIndex(of: "`") {
                    let code = String(remaining[afterTick..<endTick])
                    spans.append(.code(code))
                    remaining = remaining[remaining.index(after: endTick)...]
                } else {
                    spans.append(.plain("`"))
                    remaining = remaining[afterTick...]
                }
            } else if remaining.hasPrefix("***") {
                // Bold italic
                let afterStars = remaining.index(remaining.startIndex, offsetBy: 3)
                if let endRange = remaining[afterStars...].range(of: "***") {
                    let inner = String(remaining[afterStars..<endRange.lowerBound])
                    spans.append(.boldItalic(inner))
                    remaining = remaining[endRange.upperBound...]
                } else {
                    spans.append(.plain("***"))
                    remaining = remaining[afterStars...]
                }
            } else if remaining.hasPrefix("**") {
                // Bold (may contain inline code)
                let afterStars = remaining.index(remaining.startIndex, offsetBy: 2)
                if let endRange = remaining[afterStars...].range(of: "**") {
                    let inner = String(remaining[afterStars..<endRange.lowerBound])
                    // Check if inner is wrapped in backticks: **`code`**
                    if inner.hasPrefix("`") && inner.hasSuffix("`") && inner.count > 2 {
                        let code = String(inner.dropFirst().dropLast())
                        spans.append(.boldCode(code))
                    } else if inner.contains("`") {
                        // Mixed bold with code inside — parse inner spans and mark all bold
                        let innerSpans = parseInlineSpans(inner)
                        for s in innerSpans {
                            switch s {
                            case .plain(let t): spans.append(.bold(t))
                            case .code(let t): spans.append(.boldCode(t))
                            default: spans.append(s)
                            }
                        }
                    } else {
                        spans.append(.bold(inner))
                    }
                    remaining = remaining[endRange.upperBound...]
                } else {
                    spans.append(.plain("**"))
                    remaining = remaining[afterStars...]
                }
            } else if remaining.hasPrefix("*") {
                // Italic
                let afterStar = remaining.index(after: remaining.startIndex)
                if let endIdx = remaining[afterStar...].firstIndex(of: "*") {
                    let inner = String(remaining[afterStar..<endIdx])
                    spans.append(.italic(inner))
                    remaining = remaining[remaining.index(after: endIdx)...]
                } else {
                    spans.append(.plain("*"))
                    remaining = remaining[afterStar...]
                }
            } else {
                // Should not reach here, but safety
                spans.append(.plain(String(remaining.prefix(1))))
                remaining = remaining[remaining.index(after: remaining.startIndex)...]
            }
        }

        return spans
    }

    // MARK: - Parsing

    private func parseAllBlocks(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var remaining = text
        let headingPattern = #"^(#{1,4})\s+(.+)$"#
        let listPattern = #"^(\s*)([-*+]|\d+\.)\s+(.+)$"#
        let dividerPattern = #"^(\s*[-*_]\s*){3,}$"#

        while !remaining.isEmpty {
            // Code block
            if let codeStart = remaining.range(of: "```") {
                let before = String(remaining[remaining.startIndex..<codeStart.lowerBound])
                if !before.isEmpty {
                    blocks.append(contentsOf: parseNonCodeBlocks(before, headingPattern: headingPattern, listPattern: listPattern, dividerPattern: dividerPattern))
                }
                remaining = String(remaining[codeStart.upperBound...])
                // Skip language identifier
                if let newline = remaining.firstIndex(of: "\n") {
                    remaining = String(remaining[remaining.index(after: newline)...])
                }
                if let end = remaining.range(of: "```") {
                    let code = String(remaining[remaining.startIndex..<end.lowerBound])
                    blocks.append(.codeBlock(code.trimmingCharacters(in: .newlines)))
                    remaining = String(remaining[end.upperBound...])
                } else {
                    blocks.append(.codeBlock(remaining.trimmingCharacters(in: .newlines)))
                    remaining = ""
                }
                continue
            }

            // No more code blocks
            blocks.append(contentsOf: parseNonCodeBlocks(remaining, headingPattern: headingPattern, listPattern: listPattern, dividerPattern: dividerPattern))
            remaining = ""
        }

        return blocks
    }

    private func parseNonCodeBlocks(_ text: String, headingPattern: String, listPattern: String, dividerPattern: String) -> [Block] {
        var blocks: [Block] = []
        var paragraphLines: [String] = []
        let lines = text.components(separatedBy: "\n")

        let headingRegex = try? NSRegularExpression(pattern: headingPattern, options: .anchorsMatchLines)
        let listRegex = try? NSRegularExpression(pattern: listPattern, options: .anchorsMatchLines)
        let dividerRegex = try? NSRegularExpression(pattern: dividerPattern, options: .anchorsMatchLines)

        // Detect table regions
        var inTable = false
        var tableLines: [String] = []

        func flushParagraph() {
            let text = paragraphLines.joined(separator: "\n")
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(.paragraph(text))
            }
            paragraphLines = []
        }

        func flushTable() {
            if !tableLines.isEmpty {
                blocks.append(.table(tableLines.joined(separator: "\n")))
                tableLines = []
            }
            inTable = false
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            let isTableLine = trimmed.hasPrefix("|") && trimmed.hasSuffix("|")

            if isTableLine {
                if !inTable {
                    flushParagraph()
                    inTable = true
                }
                tableLines.append(line)
                continue
            } else if inTable {
                flushTable()
            }

            // Heading
            if let match = headingRegex?.firstMatch(in: line, range: range),
               let hashRange = Range(match.range(at: 1), in: line),
               let textRange = Range(match.range(at: 2), in: line) {
                flushParagraph()
                blocks.append(.heading(level: line[hashRange].count, text: String(line[textRange])))
                continue
            }

            // Divider
            if let _ = dividerRegex?.firstMatch(in: line, range: range), trimmed.count >= 3 {
                flushParagraph()
                blocks.append(.divider)
                continue
            }

            // List item
            if let match = listRegex?.firstMatch(in: line, range: range),
               let indentRange = Range(match.range(at: 1), in: line),
               let markerRange = Range(match.range(at: 2), in: line),
               let textRange = Range(match.range(at: 3), in: line) {
                flushParagraph()
                let indent = line[indentRange].count / 2
                let marker = String(line[markerRange])
                let ordered = marker.hasSuffix(".")
                let number = ordered ? Int(marker.dropLast()) : nil
                blocks.append(.listItem(indent: indent, ordered: ordered, number: number, text: String(line[textRange])))
                continue
            }

            // Empty line = paragraph break
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            paragraphLines.append(line)
        }

        if inTable { flushTable() }
        flushParagraph()

        return blocks
    }

    // MARK: - Table rendering

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
                let inner = String(trimmed.dropFirst().dropLast())
                let isSep = inner.allSatisfy { $0 == "-" || $0 == "|" || $0 == ":" || $0 == " " }
                    && inner.contains("-")
                let cells = inner.components(separatedBy: "|")
                return TableRow(cells: cells, isSeparator: isSep)
            }
    }
}
