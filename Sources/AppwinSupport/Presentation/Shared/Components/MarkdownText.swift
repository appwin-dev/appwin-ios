// Light Markdown rendering for chat bubbles, and later for FAQ answers.
// Handles `#` headings, `-`/`*`/`1.` lists and inline styling (bold, italic,
// links). No code blocks: out of scope for the Support SDK.
//
// Why a hand-rolled renderer rather than `Text(AttributedString(markdown:))`?
// Two traps in `AttributedString`:
//  1. it parses as `.inlineOnlyPreservingWhitespace` by default, so blocks
//     (`#`, lists) are ignored and left as raw text;
//  2. even in `.full`, a heading becomes a `presentationIntent: .header` with
//     no visual style - SwiftUI does not draw it any bigger.
// So we split into blocks ourselves, line by line, and apply our own fonts.
// Inline styling stays delegated to `AttributedString`, which also gives
// tappable links for free.

import SwiftUI

struct MarkdownText: View {
    private let blocks: [Block]
    /// Base text colour; the bubble decides between `onAccent` and `textPrimary`.
    private let color: Color
    /// Paragraph body, `text-sm` in the SaaS bubbles.
    private let bodyFont: Font?

    @Environment(\.appwinTheme) private var theme

    init(_ text: String, color: Color, bodyFont: Font? = nil) {
        self.blocks = Self.parse(text)
        self.color = color
        self.bodyFont = bodyFont
    }

    private var resolvedBodyFont: Font {
        bodyFont ?? theme.fonts.body
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
    }

    // MARK: - Block rendering

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case .blank:
            Color.clear.frame(height: theme.spacing.xs)

        case let .heading(level, text):
            // Police appliquée DANS l'AttributedString (pas `.font` sur le View) :
            // sinon SwiftUI écrase le gras/italique inline.
            styledInline(text, base: headingFont(level))

        case let .bullet(text):
            listRow(marker: "•", text: text)

        case let .ordered(number, text):
            listRow(marker: "\(number).", text: text)

        case let .paragraph(text):
            styledInline(text, base: resolvedBodyFont)
        }
    }

    private func listRow(marker: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing.xs) {
            Text(marker).font(resolvedBodyFont).foregroundColor(color)
            styledInline(text, base: resolvedBodyFont)
        }
    }

    /// Inline markdown (bold, italic, links) with the base font merged run by
    /// run: a `.font` modifier on `Text(AttributedString)` would cancel the bold.
    private func styledInline(_ s: String, base: Font) -> Text {
        Text(Self.inlineAttributed(s, baseFont: base)).foregroundColor(color)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1:  return theme.fonts.title      // 22 bold
        case 2:  return theme.fonts.headline   // 18 semibold
        default: return theme.fonts.body.bold() // H3+ → corps en gras
        }
    }

    // MARK: - Parsing (pure and static, so no shared state)

    private enum Block {
        case heading(level: Int, text: String)
        case bullet(text: String)
        case ordered(number: String, text: String)
        case paragraph(text: String)
        case blank
    }

    private static func parse(_ text: String) -> [Block] {
        text.components(separatedBy: "\n").map { rawLine in
            // TipTap and CommonMark hard-break is a trailing `\`. Without this,
            // bubbles show literal backslashes.
            let line = stripTrailingHardBreak(rawLine.trimmingCharacters(in: .whitespaces))
            if line.isEmpty { return .blank }
            if let (level, rest) = heading(line) { return .heading(level: level, text: rest) }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                return .bullet(text: String(line.dropFirst(2)))
            }
            if let (number, rest) = ordered(line) { return .ordered(number: number, text: rest) }
            return .paragraph(text: line)
        }
    }

    /// Strips a trailing `\` hard break. A line that was only `\` becomes blank.
    private static func stripTrailingHardBreak(_ line: String) -> String {
        guard line.hasSuffix("\\") else { return line }
        return String(line.dropLast()).trimmingCharacters(in: .whitespaces)
    }

    /// `# text` through `###### text`, returning the level and the remainder.
    private static func heading(_ s: String) -> (Int, String)? {
        var level = 0
        var idx = s.startIndex
        while idx < s.endIndex, s[idx] == "#", level < 6 {
            level += 1
            idx = s.index(after: idx)
        }
        guard level > 0, idx < s.endIndex, s[idx] == " " else { return nil }
        return (level, String(s[s.index(after: idx)...]))
    }

    /// `12. text`, returning the number and the remainder. The real number is kept.
    private static func ordered(_ s: String) -> (String, String)? {
        guard let dot = s.range(of: ". ") else { return nil }
        let prefix = s[s.startIndex..<dot.lowerBound]
        guard !prefix.isEmpty, prefix.allSatisfy(\.isNumber) else { return nil }
        return (String(prefix), String(s[dot.upperBound...]))
    }

    /// Inline parsing (bold, italic, links) plus the base font applied run by
    /// run. Falls back to plain text when the markdown is invalid, so it never
    /// crashes.
    private static func inlineAttributed(_ s: String, baseFont: Font? = nil) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        var attr = (try? AttributedString(markdown: s, options: options)) ?? AttributedString(s)
        guard let baseFont else { return attr }

        attr.font = baseFont
        for run in attr.runs {
            guard let intent = run.inlinePresentationIntent else { continue }
            var font = baseFont
            if intent.contains(.stronglyEmphasized) { font = font.bold() }
            if intent.contains(.emphasized) { font = font.italic() }
            attr[run.range].font = font
        }
        return attr
    }

    // MARK: - Preview (reused by the conversation list)

    /// One-line bare text: block markers are stripped and the whole thing is
    /// flattened into a sentence. Inline styling is not applied here.
    static func plainText(_ text: String) -> String {
        parse(text).compactMap { block -> String? in
            switch block {
            case .blank: return nil
            case let .heading(_, t): return t
            case let .bullet(t): return t
            case let .ordered(_, t): return t
            case let .paragraph(t): return t
            }
        }.joined(separator: " ")
    }

    /// Fully flat text, blocks and inline syntax removed, for somewhere that
    /// only accepts a raw `String` such as a navigation bar title.
    static func plainString(_ text: String) -> String {
        String(inlineAttributed(plainText(text)).characters)
    }

    /// One-line preview for a list: blocks flattened, inline styling kept, but
    /// links tinted `linkColor` and not tappable, since the URL is removed.
    static func previewAttributed(_ text: String, linkColor: Color) -> AttributedString {
        var attr = inlineAttributed(plainText(text))
        for range in attr.runs.filter({ $0.link != nil }).map(\.range) {
            attr[range].link = nil
            attr[range].foregroundColor = linkColor
        }
        return attr
    }
}
