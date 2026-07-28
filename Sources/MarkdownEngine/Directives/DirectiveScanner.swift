//
//  DirectiveScanner.swift
//  MarkdownEngine
//
//  The parser side of the directive seam. Called from
//  `InlineParser.matchClaimedSpan` AFTER every built-in, so a directive can
//  never take text away from core markdown — the same precedence rule
//  extension spans follow.
//
//  Self-contained by design: the scanner re-implements the two helpers it
//  needs (`isEscaped`, balanced-delimiter scanning) rather than reaching into
//  `InlineParser`'s private ones, so the whole seam is one directory of new
//  files plus a four-line hook.
//
//  Rejection is always silent and always means "stays literal text": an
//  unregistered name, a malformed call, a wrong-form call, a run crossing a
//  line break. Nothing here can produce a partial construct.
//
//  Because the scanner runs inside `scanLinkFamily` (pass 3), a directive
//  inside a code span or `$…$` is already claimed and never fires.
//

import Foundation

/// A matched directive, in absolute UTF-16 coordinates. Neutral value type:
/// `InlineParser` converts it into its own private `Span` at the call site.
struct DirectiveMatch: Equatable {
    /// AST node id — already namespaced via `DirectiveRegistry.nodeID(for:)`.
    let nodeID: String
    let range: NSRange
    /// The name run, without the marker (`font` in `@font(…)`).
    let nameRange: NSRange
    /// Inside the parens; `nil` when the call has no argument list.
    let argumentsRange: NSRange?
    /// Inside the braces; `nil` for a self-contained call.
    let bodyRange: NSRange?
    /// Ranges that shrink when the caret leaves: `[prefix, closingBrace]` for
    /// a container, empty for a self-contained call (Phase 1 renders those
    /// literally — the glyph pass that collapses them lands in Phase 3).
    let markers: [NSRange]
    /// Range carrying the node's content: the body for a container, the whole
    /// call for a self-contained one.
    let contentRange: NSRange
    /// Whether the content is re-parsed as markdown.
    let parsesContent: Bool
}

enum DirectiveScanner {

    private static let lparen: unichar = 0x28
    private static let rparen: unichar = 0x29
    private static let lbrace: unichar = 0x7B
    private static let rbrace: unichar = 0x7D
    private static let backslash: unichar = 0x5C
    private static let quote: unichar = 0x22
    private static let dot: unichar = 0x2E
    private static let newline: unichar = 0x0A
    private static let carriageReturn: unichar = 0x0D

    /// Try to match a directive starting at `i`. Returns nil for every
    /// rejection — the candidate then stays literal text.
    static func match(_ ns: NSString, len: Int, at i: Int, registry: DirectiveRegistry) -> DirectiveMatch? {
        guard !registry.isEmpty, i >= 0, i < len else { return nil }
        let marker = ns.character(at: i)
        guard let table = registry.byMarker[marker], !table.isEmpty else { return nil }

        // Left boundary: start-of-line, whitespace, or opening punctuation.
        // `name@example.com` therefore never opens a directive, and a `@@` run
        // stays literal (mirrors `InlineSyntax.rejectsOpenerRun`).
        if i > 0 {
            let previous = ns.character(at: i - 1)
            guard previous != marker, isBoundary(previous) else { return nil }
        }
        guard !isEscaped(i, ns) else { return nil }

        // Name: ident ('.' ident)*
        var cursor = i + 1
        let nameStart = cursor
        guard cursor < len, isIdentStart(ns.character(at: cursor)) else { return nil }
        while cursor < len {
            let c = ns.character(at: cursor)
            if isIdentChar(c) {
                cursor += 1
            } else if c == dot, cursor + 1 < len, isIdentStart(ns.character(at: cursor + 1)) {
                cursor += 1
            } else {
                break
            }
        }
        let nameRange = NSRange(location: nameStart, length: cursor - nameStart)

        // REGISTERED NAMES ONLY — the property that makes this safe to enable
        // over an existing document corpus.
        guard let entry = table[ns.substring(with: nameRange)] else { return nil }

        // Optional argument list `( … )`: balanced, single line.
        var argumentsRange: NSRange?
        if cursor < len, ns.character(at: cursor) == lparen {
            guard let close = balanced(ns, len: len, from: cursor + 1, open: lparen, close: rparen) else { return nil }
            argumentsRange = NSRange(location: cursor + 1, length: close - (cursor + 1))
            cursor = close + 1
        }

        // Optional body `{ … }`: balanced, single line, escape-aware.
        var bodyRange: NSRange?
        if cursor < len, ns.character(at: cursor) == lbrace {
            guard let close = balanced(ns, len: len, from: cursor + 1, open: lbrace, close: rbrace) else { return nil }
            bodyRange = NSRange(location: cursor + 1, length: close - (cursor + 1))
            cursor = close + 1
        }

        // Form check — a mismatched call stays literal rather than rendering
        // half-configured.
        switch entry.form {
        case .selfContained: guard bodyRange == nil else { return nil }
        case .container:     guard bodyRange != nil else { return nil }
        case .either:        break
        }

        let range = NSRange(location: i, length: cursor - i)

        if let body = bodyRange {
            // Markers are what shrinks when the caret leaves: the whole
            // `@font(size: 18){` prefix and the closing `}`, leaving only the
            // styled body visible.
            let prefix = NSRange(location: i, length: body.location - i)
            let closingBrace = NSRange(location: NSMaxRange(body), length: 1)
            return DirectiveMatch(
                nodeID: DirectiveRegistry.nodeID(for: entry.id),
                range: range,
                nameRange: nameRange,
                argumentsRange: argumentsRange,
                bodyRange: body,
                markers: [prefix, closingBrace],
                contentRange: body,
                parsesContent: entry.parsesBody
            )
        }

        // Self-contained: no markers in Phase 1, so the call renders as plain
        // literal text instead of collapsing to nothing. It is still CLAIMED,
        // so emphasis and autolinking can't fire inside it, and it still
        // projects a token — the glyph pass in Phase 3 only has to add
        // presentation.
        return DirectiveMatch(
            nodeID: DirectiveRegistry.nodeID(for: entry.id),
            range: range,
            nameRange: nameRange,
            argumentsRange: argumentsRange,
            bodyRange: nil,
            markers: [],
            contentRange: range,
            parsesContent: false
        )
    }

    // MARK: - Character classes

    /// `[A-Za-z_]`
    private static func isIdentStart(_ c: unichar) -> Bool {
        (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F
    }

    /// `[A-Za-z0-9_-]`
    private static func isIdentChar(_ c: unichar) -> Bool {
        isIdentStart(c) || (c >= 0x30 && c <= 0x39) || c == 0x2D
    }

    /// Characters a directive may open after: whitespace, line breaks, and
    /// opening punctuation. Anything alphanumeric rejects — the email rule.
    private static func isBoundary(_ c: unichar) -> Bool {
        switch c {
        case 0x20, 0x09, 0x0A, 0x0D:            return true   // space tab \n \r
        case 0x28, 0x5B, 0x7B, 0x3C:            return true   // ( [ { <
        case 0x22, 0x27:                        return true   // " '
        case 0x2013, 0x2014, 0x201C, 0x2018:    return true   // – — “ ‘
        case 0x3E:                              return true   // > blockquote marker
        default:                                return false
        }
    }

    // MARK: - Scanning helpers

    /// Index of the delimiter balancing the run starting at `from`, or nil
    /// when the run is unbalanced or crosses a line break. Escaped delimiters
    /// and delimiters inside a quoted string don't count.
    private static func balanced(_ ns: NSString, len: Int, from: Int, open: unichar, close: unichar) -> Int? {
        var depth = 1
        var inQuote = false
        var k = from
        while k < len {
            let c = ns.character(at: k)
            if c == newline || c == carriageReturn { return nil }
            if !isEscaped(k, ns) {
                if c == quote {
                    inQuote.toggle()
                } else if !inQuote {
                    if c == open { depth += 1 }
                    if c == close {
                        depth -= 1
                        if depth == 0 { return k }
                    }
                }
            }
            k += 1
        }
        return nil
    }

    /// Whether the character at `index` is preceded by an odd number of
    /// backslashes. Mirrors `InlineParser.isEscaped`, kept local so this file
    /// has no private dependency on the parser.
    private static func isEscaped(_ index: Int, _ ns: NSString) -> Bool {
        var count = 0
        var k = index - 1
        while k >= 0, ns.character(at: k) == backslash {
            count += 1
            k -= 1
        }
        return count % 2 == 1
    }
}
