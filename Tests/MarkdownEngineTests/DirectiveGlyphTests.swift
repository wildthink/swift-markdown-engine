//
//  DirectiveGlyphTests.swift
//  MarkdownEngineTests
//
//  Phase 3 — a self-contained directive draws a glyph in place of its
//  collapsed source, on the same mechanism inline LaTeX uses: the characters
//  stay in the text, the first one carries the image and enough kern to occupy
//  its width, and the rest collapse to nothing.
//
//  The failure mode worth guarding is a glyph that can't be produced: the
//  source must stay VISIBLE rather than collapsing to an empty gap the user
//  can't see, select, or fix.
//

import AppKit
import Foundation
import Testing
@testable import MarkdownEngine

@Suite("Directives — self-contained glyphs")
struct DirectiveGlyphTests {

    private let base: CGFloat = 14
    private var fontName: String { NSFont.systemFont(ofSize: 14).fontName }
    private var hiddenSize: CGFloat { MarkdownEditorConfiguration.default.markers.hiddenMarkerFontSize }

    /// A directive whose symbol name the system cannot resolve.
    private struct BrokenSymbolDirective: MarkdownDirective {
        var syntax: DirectiveSyntax { DirectiveSyntax(name: "broken", form: .selfContained) }
        func presentation(arguments: DirectiveArguments, context: DirectiveContext) -> DirectivePresentation {
            .symbol(name: "definitely.not.a.real.sf.symbol", tint: nil)
        }
    }

    /// A directive that declines to draw anything.
    private struct PlainDirective: MarkdownDirective {
        var syntax: DirectiveSyntax { DirectiveSyntax(name: "plain", form: .selfContained) }
    }

    /// A directive supplying its own image, sized from an argument.
    private struct SwatchDirective: MarkdownDirective {
        var syntax: DirectiveSyntax {
            DirectiveSyntax(name: "swatch", form: .selfContained,
                            parameters: [.init(label: "size", kind: .number)])
        }
        func presentation(arguments: DirectiveArguments, context: DirectiveContext) -> DirectivePresentation {
            let side = arguments.number("size").map { CGFloat($0) } ?? 10
            return .image(NSImage(size: CGSize(width: side, height: side)), baselineOffset: 0)
        }
    }

    private var configuration: MarkdownEditorConfiguration {
        MarkdownEditorConfiguration(directives: [
            PageBreakDirective(), BrokenSymbolDirective(), PlainDirective(), SwatchDirective(),
        ])
    }

    private func style(_ text: String, caret: Int = -1) -> [StyledRange] {
        MarkdownASTStyler.styleAttributes(
            text: text, fontName: fontName, fontSize: base,
            caretLocation: caret, configuration: configuration
        )
    }

    /// Attributes covering the first character of `needle`.
    private func firstCharAttributes(_ text: String, _ needle: String, caret: Int = -1)
        -> [NSAttributedString.Key: Any] {
        let position = (text as NSString).range(of: needle).location
        var merged: [NSAttributedString.Key: Any] = [:]
        for (range, attributes) in style(text, caret: caret)
        where NSLocationInRange(position, range) {
            merged.merge(attributes) { _, new in new }
        }
        return merged
    }

    // MARK: - Drawing

    @Test("the glyph rides on the call's first character")
    func glyphOnFirstCharacter() {
        let attributes = firstCharAttributes("a @pagebreak b", "@pagebreak")
        #expect(attributes[.latexImage] is NSImage)
        #expect(attributes[.latexBounds] is NSValue)
    }

    @Test("the glyph is sized to the inherited font")
    func glyphSizedToFont() {
        let small = firstCharAttributes("@pagebreak", "@pagebreak")[.latexImage] as? NSImage
        let attrs = MarkdownASTStyler.styleAttributes(
            text: "# @pagebreak", fontName: fontName, fontSize: base,
            caretLocation: -1, configuration: configuration
        )
        let position = ("# @pagebreak" as NSString).range(of: "@pagebreak").location
        var large: NSImage?
        for (range, a) in attrs where NSLocationInRange(position, range) {
            if let image = a[.latexImage] as? NSImage { large = image }
        }
        // A heading's larger font must yield a larger glyph.
        #expect(small != nil && large != nil)
        #expect((large?.size.height ?? 0) > (small?.size.height ?? 0))
    }

    @Test("the first character carries kern for the glyph's width")
    func firstCharacterReservesWidth() {
        let attributes = firstCharAttributes("@pagebreak", "@pagebreak")
        let image = attributes[.latexImage] as? NSImage
        let kern = attributes[.kern] as? CGFloat ?? 0
        // Kern must account for most of the image width (minus the shrunk
        // character's own negligible advance).
        #expect(kern > 0)
        #expect(kern <= (image?.size.width ?? 0))
    }

    @Test("the remaining characters collapse")
    func remainderCollapses() {
        let text = "@pagebreak"
        let tail = (text as NSString).range(of: "pagebreak")
        var sawCollapse = false
        for (range, attributes) in style(text) where NSIntersectionRange(range, tail).length > 0 {
            if (attributes[.font] as? NSFont)?.pointSize == hiddenSize,
               (attributes[.kern] as? CGFloat ?? 0) < 0 {
                sawCollapse = true
            }
        }
        #expect(sawCollapse)
    }

    @Test("a directive-supplied image is used as given")
    func suppliedImageIsUsed() {
        let attributes = firstCharAttributes("@swatch(size: 24)", "@swatch")
        #expect((attributes[.latexImage] as? NSImage)?.size.width == 24)
    }

    @Test("arguments reach a self-contained presentation")
    func argumentsReachPresentation() {
        #expect((firstCharAttributes("@swatch(size: 8)", "@swatch")[.latexImage] as? NSImage)?.size.width == 8)
        #expect((firstCharAttributes("@swatch(size: 32)", "@swatch")[.latexImage] as? NSImage)?.size.width == 32)
    }

    // MARK: - Caret reveal

    @Test("the caret inside reveals the source and drops the glyph")
    func caretRevealsSource() {
        let attributes = firstCharAttributes("@pagebreak", "@pagebreak", caret: 3)
        #expect(attributes[.latexImage] == nil)
        #expect((attributes[.font] as? NSFont)?.pointSize != hiddenSize)
    }

    // MARK: - Degradation

    @Test("an unresolvable symbol leaves the source visible, not an empty gap")
    func brokenSymbolStaysVisible() {
        // The important failure mode: collapsing source we can't replace would
        // leave a blank the user can neither see nor fix.
        let attributes = firstCharAttributes("@broken", "@broken")
        #expect(attributes[.latexImage] == nil)
        #expect((attributes[.font] as? NSFont)?.pointSize != hiddenSize)
    }

    @Test("a directive declining to draw leaves its source visible")
    func literalPresentationStaysVisible() {
        let attributes = firstCharAttributes("@plain", "@plain")
        #expect(attributes[.latexImage] == nil)
        #expect((attributes[.font] as? NSFont)?.pointSize != hiddenSize)
    }

    @Test("spell-check is suppressed over a directive call")
    func spellCheckSuppressed() {
        #expect(firstCharAttributes("@pagebreak", "@pagebreak")[.spellingState] as? Int == 0)
    }

    // MARK: - Isolation

    @Test("a glyph does not disturb the surrounding text")
    func neighboursUnaffected() {
        let text = "before @pagebreak after"
        let position = (text as NSString).range(of: "after").location
        for (range, attributes) in style(text) where NSLocationInRange(position, range) {
            #expect(attributes[.latexImage] == nil)
            #expect((attributes[.font] as? NSFont)?.pointSize != hiddenSize)
        }
    }

    // MARK: - IconDirective

    @Test("an icon draws the symbol named in its positional argument")
    func iconDrawsNamedSymbol() {
        let configuration = MarkdownEditorConfiguration(directives: [IconDirective()])
        func image(_ text: String) -> NSImage? {
            let position = (text as NSString).range(of: "@icon").location
            var found: NSImage?
            for (range, attributes) in MarkdownASTStyler.styleAttributes(
                text: text, fontName: fontName, fontSize: base,
                caretLocation: -1, configuration: configuration
            ) where NSLocationInRange(position, range) {
                if let candidate = attributes[.latexImage] as? NSImage { found = candidate }
            }
            return found
        }
        #expect(image("@icon(star.fill)") != nil)
        #expect(image("@icon(checkmark.circle.fill, color: green)") != nil)
        // A dotted symbol name survives argument splitting.
        #expect(image("@icon(arrow.down.to.line)") != nil)
        // An unknown symbol leaves the source visible.
        #expect(image("@icon(not.a.symbol.at.all)") == nil)
    }

    @Test("scoped styling matches the full pass for a glyph-bearing paragraph")
    func scopedMatchesFull() {
        let text = "intro\n\nbefore @pagebreak after\n\noutro"
        let ns = text as NSString
        let paragraph = ns.paragraphRange(for: ns.range(of: "@pagebreak"))
        func digest(_ scoped: [NSRange]?) -> String {
            MarkdownASTStyler.styleAttributes(
                text: text, fontName: fontName, fontSize: base,
                scopedRanges: scoped, configuration: configuration
            )
            .filter { NSIntersectionRange($0.range, paragraph).length > 0 }
            .map { "\($0.range.location):\($0.range.length)[\($0.attributes.keys.map(\.rawValue).sorted().joined(separator: ","))]" }
            .sorted()
            .joined(separator: "\n")
        }
        #expect(digest([paragraph]) == digest(nil))
    }
}
