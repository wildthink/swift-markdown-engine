//
//  DirectiveStylingTests.swift
//  MarkdownEngineTests
//
//  Phase 1 styling behaviour for directives. The styler has no directive case
//  yet — directives ride the extension-node path — so what this suite locks in
//  is that the generic machinery already does the right thing:
//
//    * a container's syntax shrinks when the caret leaves, and its body
//      survives as ordinary styled markdown;
//    * a self-contained call renders as plain literal text (no glyph until
//      Phase 3, and crucially nothing that collapses it to nothing);
//    * an unknown directive id can't crash or restyle a neighbour.
//
//  Phase 2 replaces the "body has no directive attributes" expectations with
//  real font composition; these tests are the before-picture.
//

import AppKit
import Foundation
import Testing
@testable import MarkdownEngine

@Suite("Directives — Phase 1 styling")
struct DirectiveStylingTests {

    private let base: CGFloat = 14
    private var fontName: String { NSFont.systemFont(ofSize: 14).fontName }

    private var configuration: MarkdownEditorConfiguration {
        MarkdownEditorConfiguration(directives: [FontDirective(), PageBreakDirective()])
    }

    private func style(_ text: String, caret: Int = -1) -> [StyledRange] {
        MarkdownASTStyler.styleAttributes(
            text: text, fontName: fontName, fontSize: base,
            caretLocation: caret, configuration: configuration
        )
    }

    /// Effective font at `pos`: the last styled range covering it that sets `.font`.
    private func font(in attrs: [StyledRange], at pos: Int) -> NSFont? {
        var result: NSFont?
        for (range, a) in attrs where NSLocationInRange(pos, range) {
            if let f = a[.font] as? NSFont { result = f }
        }
        return result
    }

    private var hiddenSize: CGFloat { MarkdownEditorConfiguration.default.markers.hiddenMarkerFontSize }

    /// Canonical, order-independent digest of styled ranges, so two style runs
    /// can be compared. Local twin of the one in `MarkdownASTStylerTests`
    /// (that one is file-private).
    private func digest(_ ranges: [StyledRange]) -> String {
        ranges
            .map { entry in
                let keys = entry.attributes.keys.map(\.rawValue).sorted().joined(separator: ",")
                return "\(entry.range.location):\(entry.range.length)[\(keys)]"
            }
            .sorted()
            .joined(separator: "\n")
    }

    // MARK: - Container

    @Test("a container's syntax shrinks when the caret is elsewhere")
    func syntaxShrinksWhenInactive() {
        let attrs = style("@font(size: 18){hello} tail")
        // Inside the `@font(size: 18){` prefix.
        #expect(font(in: attrs, at: 2)?.pointSize == hiddenSize)
    }

    @Test("the body keeps the document font, not the shrunk marker font")
    func bodyKeepsBodyFont() {
        let text = "@font(size: 18){hello} tail"
        let attrs = style(text)
        let bodyStart = (text as NSString).range(of: "hello").location
        let bodyFont = font(in: attrs, at: bodyStart)
        #expect(bodyFont == nil || bodyFont?.pointSize == base)
    }

    @Test("the caret inside the call reveals its syntax")
    func syntaxRevealsWhenActive() {
        let attrs = style("@font(size: 18){hello}", caret: 3)
        #expect(font(in: attrs, at: 2)?.pointSize != hiddenSize)
    }

    @Test("markup inside the body still styles")
    func bodyMarkupStillStyles() {
        let text = "@font(size: 18){**bold**}"
        let attrs = style(text)
        let boldStart = (text as NSString).range(of: "bold").location
        let traits = font(in: attrs, at: boldStart)?.fontDescriptor.symbolicTraits
        #expect(traits?.contains(.bold) == true)
    }

    // MARK: - Self-contained

    @Test("a self-contained call renders as literal text — nothing collapses it")
    func selfContainedStaysVisible() {
        let text = "before @pagebreak after"
        let attrs = style(text)
        let location = (text as NSString).range(of: "@pagebreak").location
        // No shrink font and no negative kern anywhere in the call.
        for (range, a) in attrs where NSIntersectionRange(range, NSRange(location: location, length: 10)).length > 0 {
            #expect((a[.font] as? NSFont)?.pointSize != hiddenSize)
            #expect((a[.kern] as? CGFloat ?? 0) >= 0)
        }
    }

    // MARK: - Isolation

    @Test("text after a directive is unaffected")
    func neighbourUnaffected() {
        let text = "@font(size: 18){hello} plain tail"
        let attrs = style(text)
        let tail = (text as NSString).range(of: "plain tail").location
        let tailFont = font(in: attrs, at: tail)
        #expect(tailFont == nil || tailFont?.pointSize == base)
    }

    @Test("an unregistered directive styles as ordinary text")
    func unregisteredIsPlain() {
        let attrs = MarkdownASTStyler.styleAttributes(
            text: "@font(size: 18){hello}", fontName: fontName, fontSize: base,
            caretLocation: -1, configuration: .default
        )
        #expect(font(in: attrs, at: 2)?.pointSize != hiddenSize)
    }

    @Test("styling a directive-bearing document scoped to one paragraph matches the full pass")
    func scopedMatchesFull() {
        let text = "intro line\n\n@font(size: 18){hello} tail\n\noutro"
        let ns = text as NSString
        let paragraph = ns.paragraphRange(for: ns.range(of: "@font"))
        func keys(_ scoped: [NSRange]?) -> String {
            let ranges = MarkdownASTStyler.styleAttributes(
                text: text, fontName: fontName, fontSize: base,
                scopedRanges: scoped, configuration: configuration
            ).filter { NSIntersectionRange($0.range, paragraph).length > 0 }
            return digest(ranges)
        }
        #expect(keys([paragraph]) == keys(nil))
    }
}
