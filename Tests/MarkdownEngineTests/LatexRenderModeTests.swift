//
//  LatexRenderModeTests.swift
//  MarkdownEngineTests
//

import AppKit
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("LaTeX render modes", .serialized)
struct LatexRenderModeTests {
    private struct LegacyRenderer: LatexRenderer {
        func render(
            latex: String,
            fontSize: CGFloat,
            theme: MarkdownEditorTheme
        ) -> LatexRenderResult? {
            guard latex == #"\sum_{i=1}^{n} x_i"# else { return nil }
            return testLatexResult
        }
    }

    private struct ModeCheckingRenderer: LatexRenderer {
        let expectedLatex: String
        let expectedMode: LatexRenderMode

        func render(
            latex: String,
            fontSize: CGFloat,
            theme: MarkdownEditorTheme
        ) -> LatexRenderResult? {
            nil
        }

        func render(
            latex: String,
            mode: LatexRenderMode,
            fontSize: CGFloat,
            theme: MarkdownEditorTheme
        ) -> LatexRenderResult? {
            guard latex == expectedLatex, mode == expectedMode else { return nil }
            return testLatexResult
        }
    }

    /// Deterministic native-image renderer for exercising the editor's TextKit
    /// integration independently of a particular math engine. The SwaTex package
    /// tests exercise the real renderer; these tests isolate caret and mutation
    /// behavior in the canonical-source editor pipeline.
    private struct FixtureRenderer: LatexRenderer {
        func render(
            latex: String,
            fontSize: CGFloat,
            theme: MarkdownEditorTheme
        ) -> LatexRenderResult? {
            render(latex: latex, mode: .inline, fontSize: fontSize, theme: theme)
        }

        func render(
            latex: String,
            mode: LatexRenderMode,
            fontSize: CGFloat,
            theme: MarkdownEditorTheme
        ) -> LatexRenderResult? {
            guard !latex.isEmpty,
                  latex != #"\frac{a}{"#,
                  !latex.contains(#"\badcommand"#)
            else { return nil }
            return testLatexResult
        }
    }

    private static func configuration(latex: any LatexRenderer) -> MarkdownEditorConfiguration {
        var configuration = MarkdownEditorConfiguration.default
        configuration.services = MarkdownEditorServices(latex: latex)
        return configuration
    }

    private func makeEditor(_ source: String) -> (NativeTextViewCoordinator, NativeTextView) {
        _ = NSApplication.shared
        let configuration = Self.configuration(latex: FixtureRenderer())
        let coordinator = NativeTextViewCoordinator(
            text: .constant(""), fontName: "SF Pro Text", fontSize: 14,
            isWikiLinkActive: .constant(false), onLinkClick: nil,
            onInlineSelectionChange: nil
        )
        coordinator.configuration = configuration
        coordinator.documentId = "latex-evaluation-spike"

        let textView = NativeTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        textView.isEditable = true
        textView.allowsUndo = true
        textView.configuration = configuration
        textView.delegate = coordinator
        coordinator.textView = textView
        coordinator.rebuildTextStorageAndStyle(textView, from: source)
        return (coordinator, textView)
    }

    private func changeSelection(
        _ range: NSRange,
        coordinator: NativeTextViewCoordinator,
        textView: NativeTextView
    ) {
        textView.setSelectedRange(range)
        coordinator.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: textView)
        )
    }

    private func inlineLatexToken(
        coordinator: NativeTextViewCoordinator,
        textView: NativeTextView
    ) throws -> MarkdownToken {
        try #require(
            coordinator.parsedDocument(for: textView.string).tokens.first { $0.kind == .inlineLatex }
        )
    }

    private func hasRenderedMath(_ textView: NativeTextView, at location: Int) -> Bool {
        guard location >= 0, location < (textView.string as NSString).length else { return false }
        return textView.textStorage?.attribute(.latexImage, at: location, effectiveRange: nil) != nil
    }

    private func sourceIsVisible(_ textView: NativeTextView, at location: Int) -> Bool {
        guard location >= 0, location < (textView.string as NSString).length else { return false }
        guard let color = textView.textStorage?.attribute(
            .foregroundColor, at: location, effectiveRange: nil
        ) as? NSColor else { return true }
        return color.alphaComponent > 0
    }

    private func renderedFormulaCount(_ textView: NativeTextView) -> Int {
        guard let storage = textView.textStorage else { return 0 }
        var count = 0
        storage.enumerateAttribute(
            .latexImage,
            in: NSRange(location: 0, length: storage.length)
        ) { value, _, _ in
            if value != nil { count += 1 }
        }
        return count
    }

    @Test("Existing renderers receive unchanged delimiter-free LaTeX")
    func legacyRendererFallback() {
        let renderer: any LatexRenderer = LegacyRenderer()
        let rendered = renderer.render(
            latex: #"\sum_{i=1}^{n} x_i"#,
            mode: .display,
            fontSize: 14,
            theme: .default
        )

        #expect(rendered != nil)
    }

    @Test("Block and inline styling route their existing token mode")
    func blockAndInlineRouting() {
        _ = NSApplication.shared

        let block = #"\sum_{i=1}^{n} x_i"#
        let blockAttributes = MarkdownStyler.styleAttributes(
            text: "$$\n\(block)\n$$",
            fontName: "Helvetica",
            fontSize: 14,
            caretLocation: 0,
            activeTokenIndices: [],
            configuration: Self.configuration(
                latex: ModeCheckingRenderer(expectedLatex: block, expectedMode: .display)
            )
        )
        #expect(blockAttributes.contains { $0.attributes[.latexImage] != nil })

        let inlineAttributes = MarkdownStyler.styleAttributes(
            text: "before $x$ after",
            fontName: "Helvetica",
            fontSize: 14,
            caretLocation: 0,
            activeTokenIndices: [],
            configuration: Self.configuration(
                latex: ModeCheckingRenderer(expectedLatex: "x", expectedMode: .inline)
            )
        )
        #expect(inlineAttributes.contains { $0.attributes[.latexImage] != nil })
    }

    @Test("Table math is inline")
    func tableRouting() {
        _ = NSApplication.shared
        let configuration = Self.configuration(
            latex: ModeCheckingRenderer(expectedLatex: "x", expectedMode: .inline)
        )
        let cell = MarkdownStyler.formattedCellString(
            "$x$",
            baseFont: .systemFont(ofSize: 14),
            header: false,
            theme: configuration.theme,
            codeBackgroundColor: .clear,
            latex: configuration.services.latex,
            extensions: []
        )

        #expect(cell.string == "\u{FFFC}")
    }

    @Test("Caret entry reveals canonical source and exit restores native rendering")
    func caretEntryAndExit() throws {
        do {
            let source = "before $x^2$ after"
            let (coordinator, textView) = makeEditor(source)
            let token = try inlineLatexToken(coordinator: coordinator, textView: textView)

            #expect(textView.string == source)
            #expect(hasRenderedMath(textView, at: token.contentRange.location))

            changeSelection(
                NSRange(location: token.contentRange.location + 1, length: 0),
                coordinator: coordinator,
                textView: textView
            )
            #expect(textView.string == source)
            #expect(!hasRenderedMath(textView, at: token.contentRange.location))
            #expect(sourceIsVisible(textView, at: token.contentRange.location))

            changeSelection(
                NSRange(location: NSMaxRange(token.range) + 1, length: 0),
                coordinator: coordinator,
                textView: textView
            )
            #expect(textView.string == source)
            #expect(hasRenderedMath(textView, at: token.contentRange.location))
        }

        do {
            let source = "before\n$$\n\\frac{x^2}{2a}\n$$\nafter"
            let (coordinator, textView) = makeEditor(source)
            let token = try #require(
                coordinator.parsedDocument(for: textView.string).tokens.first { $0.kind == .blockLatex }
            )

            #expect(textView.string == source)
            #expect(renderedFormulaCount(textView) == 1)

            changeSelection(
                NSRange(location: token.contentRange.location + 1, length: 0),
                coordinator: coordinator,
                textView: textView
            )
            #expect(textView.string == source)
            #expect(renderedFormulaCount(textView) == 0)
            #expect(sourceIsVisible(textView, at: token.contentRange.location + 1))

            changeSelection(
                NSRange(location: NSMaxRange(token.range) + 1, length: 0),
                coordinator: coordinator,
                textView: textView
            )
            #expect(textView.string == source)
            #expect(renderedFormulaCount(textView) == 1)
        }
    }


    @Test("Arrow navigation crosses rendered math boundaries without skipping source")
    func arrowNavigation() throws {
        let (coordinator, textView) = makeEditor("a $x$ b")
        let token = try inlineLatexToken(coordinator: coordinator, textView: textView)

        changeSelection(
            NSRange(location: token.range.location - 1, length: 0),
            coordinator: coordinator,
            textView: textView
        )
        textView.moveRight(nil)
        coordinator.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: textView)
        )
        #expect(textView.selectedRange().location == token.range.location)
        #expect(!hasRenderedMath(textView, at: token.contentRange.location))

        changeSelection(
            NSRange(location: NSMaxRange(token.range), length: 0),
            coordinator: coordinator,
            textView: textView
        )
        textView.moveRight(nil)
        coordinator.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: textView)
        )
        #expect(textView.selectedRange().location == NSMaxRange(token.range) + 1)
        #expect(hasRenderedMath(textView, at: token.contentRange.location))
    }

    @Test("Selection spanning math reveals source without changing storage")
    func selectionSpanningMath() throws {
        let source = "left $x^2$ right"
        let (coordinator, textView) = makeEditor(source)
        let token = try inlineLatexToken(coordinator: coordinator, textView: textView)
        let selection = NSRange(location: token.range.location - 2, length: token.range.length + 4)

        changeSelection(selection, coordinator: coordinator, textView: textView)

        #expect(textView.selectedRange() == selection)
        #expect(textView.string == source)
        #expect(!hasRenderedMath(textView, at: token.contentRange.location))
        #expect(sourceIsVisible(textView, at: token.contentRange.location))
    }

    @Test("Delete and backspace at math boundaries leave editable raw source")
    func deleteAtBoundaries() throws {
        do {
            let (coordinator, textView) = makeEditor("a $x$ b")
            let token = try inlineLatexToken(coordinator: coordinator, textView: textView)
            changeSelection(
                NSRange(location: token.range.location, length: 0),
                coordinator: coordinator,
                textView: textView
            )
            textView.deleteForward(nil)
            #expect(textView.string == "a x$ b")
            #expect(renderedFormulaCount(textView) == 0)
        }

        do {
            let (coordinator, textView) = makeEditor("a $x$ b")
            let token = try inlineLatexToken(coordinator: coordinator, textView: textView)
            changeSelection(
                NSRange(location: NSMaxRange(token.range), length: 0),
                coordinator: coordinator,
                textView: textView
            )
            textView.deleteBackward(nil)
            #expect(textView.string == "a $x b")
            #expect(renderedFormulaCount(textView) == 0)
        }
    }

    @Test("Copy and paste round-trip literal LaTeX rather than rendered artifacts")
    func copyPaste() throws {
        let source = "a $x^2$ b"
        let (coordinator, textView) = makeEditor(source)
        let token = try inlineLatexToken(coordinator: coordinator, textView: textView)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        changeSelection(token.range, coordinator: coordinator, textView: textView)
        textView.copy(nil)
        #expect(pasteboard.string(forType: MarkdownPasteboardWriter.markdownType) == "$x^2$")

        changeSelection(
            NSRange(location: (textView.string as NSString).length, length: 0),
            coordinator: coordinator,
            textView: textView
        )
        textView.paste(nil)
        #expect(textView.string == source + "$x^2$")
    }

    @Test("Undo and redo preserve canonical LaTeX edits")
    func undoRedo() throws {
        let source = "a $x$ b"
        let (coordinator, textView) = makeEditor(source)
        let token = try inlineLatexToken(coordinator: coordinator, textView: textView)
        changeSelection(
            NSRange(location: NSMaxRange(token.contentRange), length: 0),
            coordinator: coordinator,
            textView: textView
        )

        textView.insertText("^2", replacementRange: textView.selectedRange())
        #expect(textView.string == "a $x^2$ b")

        let undoManager = try #require(coordinator.undoManager(for: textView))
        #expect(undoManager.canUndo)
        undoManager.undo()
        #expect(textView.string == source)
        #expect(undoManager.canRedo)
        undoManager.redo()
        #expect(textView.string == "a $x^2$ b")
    }

    @Test("Rapid edits keep source canonical and settle back to rendered math")
    func rapidEdits() throws {
        let (coordinator, textView) = makeEditor("a $x$ b")
        var expected = "a $x$ b"

        for digit in 0..<40 {
            let token = try inlineLatexToken(coordinator: coordinator, textView: textView)
            changeSelection(
                NSRange(location: NSMaxRange(token.contentRange), length: 0),
                coordinator: coordinator,
                textView: textView
            )
            let insertion = "+" + String(digit % 10)
            textView.insertText(insertion, replacementRange: textView.selectedRange())
            let close = expected.index(expected.endIndex, offsetBy: -3)
            expected.insert(contentsOf: insertion, at: close)
            #expect(textView.string == expected)
        }

        let finalToken = try inlineLatexToken(coordinator: coordinator, textView: textView)
        changeSelection(
            NSRange(location: NSMaxRange(finalToken.range) + 1, length: 0),
            coordinator: coordinator,
            textView: textView
        )
        #expect(textView.string == expected)
        #expect(hasRenderedMath(textView, at: finalToken.contentRange.location))
    }



    @Test("Malformed and incomplete LaTeX remain visible and editable")
    func malformedSourceFallback() {
        for source in [#"before $\frac{a}{$ after"#, #"before $\frac{a}{ after"#] {
            let (_, textView) = makeEditor(source)
            #expect(textView.string == source)
            #expect(renderedFormulaCount(textView) == 0)
            let malformedLocation = (source as NSString).range(of: #"\frac"#).location
            #expect(sourceIsVisible(textView, at: malformedLocation))
        }
    }

    @Test("A reused scrolling view retains 500 equations as canonical source")
    func scrollingReuseStress() {
        let source = (0..<500).map { "equation \($0): $x_{\($0)}^2$" }.joined(separator: "\n")
        let (coordinator, textView) = makeEditor(source)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        changeSelection(
            NSRange(location: 0, length: 0),
            coordinator: coordinator,
            textView: textView
        )

        #expect(textView.string == source)
        #expect(renderedFormulaCount(textView) == 500)

        let nsSource = source as NSString
        for index in stride(from: 0, to: 500, by: 37) {
            let needle = "$x_{\(index)}^2$"
            let range = nsSource.range(of: needle)
            #expect(range.location != NSNotFound)
            textView.scrollRangeToVisible(range)
        }

        coordinator.rebuildTextStorageAndStyle(textView, from: source)
        changeSelection(
            NSRange(location: 0, length: 0),
            coordinator: coordinator,
            textView: textView
        )
        #expect(textView.string == source)
        #expect(renderedFormulaCount(textView) == 500)
    }
}

private var testLatexResult: LatexRenderResult {
    let size = CGSize(width: 20, height: 10)
    return LatexRenderResult(image: NSImage(size: size), size: size, baselineOffset: 2)
}
