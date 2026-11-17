//
//  LinkIconTests.swift
//  MarkdownEngineTests
//
//  `MarkdownEditorServices.linkIcons`: an icon drawn before a hidden link's
//  text, by kern and drawing only — the text never changes.
//

import AppKit
import Foundation
import Testing
@testable import MarkdownEngine

@Suite("Link icons")
@MainActor
struct LinkIconTests {

    private let fontSize: CGFloat = 14
    private var fontName: String { NSFont.systemFont(ofSize: 14).fontName }

    /// Answers every web link with a fixed image and records what it was asked.
    final class Provider: LinkIconProvider, @unchecked Sendable {
        let image: NSImage
        var asked: [URL] = []
        init(template: Bool = false) {
            image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
                NSColor.black.setFill(); rect.fill(); return true
            }
            image.isTemplate = template
        }
        func icon(for url: URL) -> NSImage? {
            asked.append(url)
            return url.scheme == "mailto" ? nil : image
        }
    }

    private func configuration(_ provider: any LinkIconProvider) -> MarkdownEditorConfiguration {
        var configuration = MarkdownEditorConfiguration.default
        configuration.services = MarkdownEditorServices(linkIcons: provider)
        return configuration
    }

    private func attributes(_ text: String, caret: Int = -1,
                            _ configuration: MarkdownEditorConfiguration) -> [StyledRange] {
        _ = NSApplication.shared
        return MarkdownASTStyler.styleAttributes(text: text, fontName: fontName, fontSize: fontSize,
                                                 caretLocation: caret, configuration: configuration)
    }

    private func iconRuns(_ attrs: [StyledRange]) -> [StyledRange] {
        attrs.filter { $0.attributes[.linkIcon] != nil }
    }

    @Test("a hidden link's `[` carries the icon and the room for it")
    func hiddenLinkGetsIcon() throws {
        let provider = Provider()
        let text = "See [Example](example.com/page) here"
        let runs = iconRuns(attributes(text, configuration(provider)))
        let run = try #require(runs.first)
        #expect(runs.count == 1)
        #expect(run.range == NSRange(location: 4, length: 1))   // the `[`
        #expect((run.attributes[.kern] as? CGFloat ?? 0) > fontSize / 2)
        #expect(run.attributes[.linkIconBounds] is NSValue)
        // Asked with the destination as written: a relative one stays relative.
        #expect(provider.asked == [URL(string: "example.com/page")!])
    }

    @Test("with the caret in the link its syntax shows and the icon goes")
    func activeLinkHasNoIcon() {
        let text = "See [Example](https://example.com) here"
        #expect(iconRuns(attributes(text, caret: 7, configuration(Provider()))).isEmpty)
        // …and a link revealed by an active parent (emphasis) too.
        #expect(iconRuns(attributes("**a [b](https://x.y) c**", caret: 1, configuration(Provider()))).isEmpty)
    }

    @Test("no provider, or no icon for the link, leaves the link as it was")
    func noIcon() {
        let text = "See [Example](https://example.com) and [mail](mailto:a@b.c)"
        let plain = attributes(text, .default)
        #expect(iconRuns(plain).isEmpty)
        // The provider has none for mailto:, so only the https link gets one.
        #expect(iconRuns(attributes(text, configuration(Provider()))).count == 1)
    }

    @Test("a template icon is tinted, so it draws in the link's colour")
    func templateIsTinted() throws {
        let provider = Provider(template: true)
        let run = try #require(iconRuns(attributes("[a](https://x.y)", configuration(provider))).first)
        let image = try #require(run.attributes[.linkIcon] as? NSImage)
        #expect(image !== provider.image)
        #expect(!image.isTemplate)
    }

    @Test("the provider gets the destination as written, for the host to resolve")
    func destinationAsWritten() {
        let provider = Provider()
        _ = attributes("[a](notes/today.md) [b](https://x.y/p) [c](file:///tmp/x.md) [d](my%20file.md)",
                       configuration(provider))
        #expect(provider.asked.map(\.absoluteString) == [
            "notes/today.md", "https://x.y/p", "file:///tmp/x.md", "my%20file.md",
        ])
    }

    @Test("icons size with the heading they sit in")
    func headingIconIsLarger() throws {
        let config = configuration(Provider())
        let body = try #require(iconRuns(attributes("[a](https://x.y)", config)).first)
        let heading = try #require(iconRuns(attributes("# [a](https://x.y)", config)).first)
        let bodySide = (body.attributes[.linkIconBounds] as? NSValue)?.rectValue.width ?? 0
        let headingSide = (heading.attributes[.linkIconBounds] as? NSValue)?.rectValue.width ?? 0
        #expect(headingSide > bodySide)
    }

    // MARK: - Laid out

    @Test("laid out: the text is unchanged and the icon sits just before the link text")
    func layoutPlacesIconBeforeText() throws {
        _ = NSApplication.shared
        let text = "See [Example](https://example.com) here"
        let config = configuration(Provider())
        let tv = NativeTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        tv.configuration = config
        let (font, style) = TextStylingService.makeBaseFontAndStyle(
            fontName: fontName, fontSize: fontSize, layoutBridge: tv.layoutBridge, configuration: config)
        tv.baseFont = font
        tv.textContainer?.size = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        let storage = NSMutableAttributedString(string: text, attributes: [.font: font, .paragraphStyle: style])
        for (range, attributes) in MarkdownStyler.flattenedRuns(
            attributes(text, config), base: [.font: font, .paragraphStyle: style], documentLength: storage.length) {
            storage.setAttributes(attributes, range: range)
        }
        tv.textStorage?.setAttributedString(storage)
        #expect(tv.string == text)

        let tlm = try #require(tv.textLayoutManager)
        let delegate = MarkdownLayoutManagerDelegate()
        tlm.delegate = delegate
        tlm.invalidateLayout(for: tlm.documentRange)
        tlm.ensureLayout(for: tlm.documentRange)
        var icons: [(image: NSImage, rect: CGRect)] = []
        var textX: CGFloat?
        tlm.enumerateTextLayoutFragments(from: tlm.documentRange.location, options: [.ensuresLayout]) { fragment in
            guard let fragment = fragment as? MarkdownTextLayoutFragment else { return true }
            icons += fragment.linkIconRects(at: .zero)
            if let line = fragment.textLineFragments.first {
                // Where the `E` of Example is drawn: TextKit puts the caret between
                // `[` and `E` mid-way through the kern, so measure back from the `x`.
                textX = line.locationForCharacter(at: 6).x - HeadingHelpers.textWidth("E", font: font)
            }
            return true
        }
        let icon = try #require(icons.first)
        let x = try #require(textX)
        #expect(icons.count == 1)
        #expect(icon.rect.width > 0)
        // The icon ends before the text starts: the kern opened room for it.
        #expect(icon.rect.maxX <= x + 0.5)
        #expect(x - icon.rect.minX >= icon.rect.width)
    }
}
