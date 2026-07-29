//
//  DirectivePerformanceTests.swift
//  MarkdownEngineTests
//
//  The invariant this guards: per-keystroke restyle cost stays O(edit) —
//  independent of DOCUMENT SIZE — for a directive-heavy paragraph.
//
//  Measured on a directive-dense paragraph inside a 400-paragraph document,
//  the scoped restyle costs the same as in a 50-paragraph one (3.2ms vs
//  3.2ms), so nothing directive-related scales with the document.
//
//  What DOES scale is span density within the single edited paragraph, and
//  that is not a directive property: at equal span counts, `==highlight==`
//  spans and `[text](url)` links cost the same or more. The parser's
//  span-containment pass (`buildTree`'s `isChild`, `scanLinkFamily`'s
//  claimed-overlap check) is quadratic in spans per region, so 6x the spans
//  costs ~19x the parse regardless of which construct produced them:
//
//      n=40   highlight 0.59ms   link 0.43ms   directive 0.52ms
//      n=240  highlight 10.95ms  link 8.44ms   directive 10.39ms
//
//  So these tests assert the document-size invariant (which directives own)
//  and deliberately do NOT assert an absolute per-paragraph budget (which is
//  the parser's pre-existing behavior, tracked separately).
//

import AppKit
import Foundation
import Testing
@testable import MarkdownEngine

@Suite("Directives — performance")
struct DirectivePerformanceTests {

    private var fontName: String { NSFont.systemFont(ofSize: 16).fontName }

    private var configuration: MarkdownEditorConfiguration {
        MarkdownEditorConfiguration(directives: [FontDirective(), ColorDirective()])
    }

    /// A document of `paragraphs` paragraphs, one of which carries
    /// `directives` directive calls.
    private func document(paragraphs: Int, directives: Int) -> String {
        (0..<paragraphs).map { index in
            index == paragraphs / 2
                ? "Heavy: " + (0..<directives).map {
                    "@font(size: \(12 + $0 % 8)){word\($0)} @color(red){c\($0)}"
                  }.joined(separator: " ")
                : "Ordinary paragraph \(index) with **bold**, `code`, and a [link](https://example.com)."
        }
        .joined(separator: "\n\n")
    }

    private func heavyParagraph(in text: String) -> NSRange {
        let ns = text as NSString
        return ns.paragraphRange(for: ns.range(of: "Heavy:"))
    }

    private func styleScoped(_ text: String) -> [StyledRange] {
        MarkdownASTStyler.styleAttributes(
            text: text, fontName: fontName, fontSize: 16,
            scopedRanges: [heavyParagraph(in: text)], configuration: configuration
        )
    }

    /// Mean milliseconds per iteration.
    private func milliseconds(iterations: Int = 15, _ body: () -> Void) -> Double {
        body()   // warm caches so the first run's lazies aren't in the sample
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations { body() }
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        return Double(elapsed) / 1_000_000 / Double(iterations)
    }

    // MARK: - The invariant

    @Test("scoped restyle cost does not grow with document size")
    func costIsIndependentOfDocumentSize() {
        let small = document(paragraphs: 40, directives: 40)
        let large = document(paragraphs: 400, directives: 40)
        // Same edited paragraph, 10x the surrounding document.
        let smallCost = milliseconds { _ = styleScoped(small) }
        let largeCost = milliseconds { _ = styleScoped(large) }
        // Measures ~1.0x; 3x is loose enough for a loaded CI machine while
        // still catching a genuine O(document) regression, which would show
        // up here as 10x.
        #expect(largeCost < smallCost * 3,
                "scoped restyle grew with document size: \(smallCost)ms → \(largeCost)ms")
    }

    @Test("scoped restyle produces identical attributes regardless of document size")
    func scopedWorkIsIdenticalRegardlessOfDocumentSize() {
        // The structural counterpart of the timing test: if any pass were
        // walking the whole document, the in-scope output would differ.
        func digest(_ text: String) -> String {
            let paragraph = heavyParagraph(in: text)
            return styleScoped(text)
                .filter { NSIntersectionRange($0.range, paragraph).length > 0 }
                .map { entry in
                    let offset = entry.range.location - paragraph.location
                    let keys = entry.attributes.keys.map(\.rawValue).sorted().joined(separator: ",")
                    let size = (entry.attributes[.font] as? NSFont).map { "\($0.pointSize)" } ?? "-"
                    return "\(offset):\(entry.range.length)[\(keys)]\(size)"
                }
                .sorted()
                .joined(separator: "\n")
        }
        #expect(digest(document(paragraphs: 40, directives: 30))
             == digest(document(paragraphs: 400, directives: 30)))
    }

    @Test("a directive-free document is unaffected by a registered directive set")
    func registrationDoesNotTaxOrdinaryDocuments() {
        let text = (0..<300)
            .map { "Ordinary paragraph \($0) with **bold**, `code`, and a [link](https://example.com)." }
            .joined(separator: "\n\n")
        // Deliberately a FULL restyle, not a scoped one: a scoped restyle of a
        // single paragraph costs ~0.25ms, where run-to-run variance swamps any
        // real difference and a ratio assertion just measures noise.
        func cost(_ configuration: MarkdownEditorConfiguration) -> Double {
            milliseconds {
                _ = MarkdownASTStyler.styleAttributes(
                    text: text, fontName: fontName, fontSize: 16, configuration: configuration
                )
            }
        }
        // Registering directives must not tax documents that use none: the
        // scanner rejects on one dictionary probe per candidate character, and
        // building the registry costs ~5µs.
        #expect(cost(configuration) < cost(.default) * 1.5)
    }

    // MARK: - Density, for the record

    @Test("directives are not more expensive than equivalent built-in spans")
    func directivesAreNotWorseThanOtherSpans() {
        // Density cost belongs to the parser's span handling, not to
        // directives. If this ever fails, directives have acquired a cost the
        // other constructs don't have — which is the regression worth knowing.
        let count = 120
        let directiveText = (0..<count).map { "@font(size: 14){word\($0)}" }.joined(separator: " ")
        let highlightText = (0..<count).map { "==word\($0)==" }.joined(separator: " ")

        let directiveRegistry = configuration.extensionRegistry
        let highlightRegistry = MarkdownEditorConfiguration(extensions: [HighlightExtension()]).extensionRegistry

        let directiveCost = milliseconds { _ = DocumentAST.parse(directiveText, registry: directiveRegistry) }
        let highlightCost = milliseconds { _ = DocumentAST.parse(highlightText, registry: highlightRegistry) }
        #expect(directiveCost < highlightCost * 2,
                "directives cost \(directiveCost)ms vs \(highlightCost)ms for \(count) spans")
    }
}
