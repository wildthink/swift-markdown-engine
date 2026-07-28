//
//  BuiltinDirectives.swift
//  MarkdownEngine
//
//  Three directives that between them exercise every part of the seam, and
//  double as the "is a new command easy to write?" test. Not registered by
//  default — the core engine parses pure markdown; embedders opt in the way
//  they do for extensions:
//
//      configuration.directives = [FontDirective(), ColorDirective(), PageBreakDirective()]
//
//  `style` and `presentation` are declared here but not yet consulted by the
//  styler (Phase 2 / Phase 3). In Phase 1 a container directive's syntax
//  shrinks and its body renders as ordinary markdown; a self-contained call
//  renders as literal text.
//

import AppKit
import Foundation

// MARK: - @font(size: 18){…}  — container, font composition

/// The motivating case.
///
/// Note the FORM: a bare `@font(size: 18)` has no meaning under tree-shaped
/// semantics — there is nothing for it to apply to — so the directive requires
/// a body. That is the one place this seam departs from a LaTeX-style
/// `\font(size: 18)` sketch, and it is what keeps per-keystroke restyling
/// block-local.
public struct FontDirective: MarkdownDirective {

    /// Well-known id, so embedders can reference the directive without
    /// constructing one.
    public static let identifier = "font"

    public init() {}

    public var id: String { Self.identifier }

    public var syntax: DirectiveSyntax {
        DirectiveSyntax(
            name: Self.identifier,
            form: .container,
            parameters: [
                .init(label: "size", kind: .length,
                      documentation: "Point size, or 1.5em / 120% relative to the surrounding text."),
                .init(label: "family", kind: .string,
                      documentation: "Font family name; falls back to the editor font when unavailable."),
                .init(label: "weight", kind: .keyword(["regular", "bold"]),
                      defaultValue: .keyword("regular"),
                      documentation: "Font weight."),
            ]
        )
    }

    public var completion: DirectiveCompletion {
        DirectiveCompletion(
            id: id,
            title: "font",
            subtitle: "Set size, family, or weight for a span",
            keywords: ["size", "typeface", "typography"],
            snippet: "@font(size: |){}",
            symbolName: "textformat.size"
        )
    }

    public func style(arguments: DirectiveArguments, context: DirectiveContext) -> DirectiveStyle {
        // An invalid call mutes rather than restyles, so a typo reads as broken
        // instead of silently doing nothing.
        guard arguments.isValid else {
            return DirectiveStyle(attributes: [.foregroundColor: context.theme.disabledText])
        }
        var transform = DirectiveFontTransform()
        if let size = arguments.length("size", relativeTo: context.inheritedFont.pointSize) {
            transform.size = .absolute(size)
        }
        transform.familyName = arguments.string("family")
        if arguments.string("weight") == "bold" { transform.traits = .boldFontMask }
        return DirectiveStyle(font: transform)
    }

    public func html(arguments: DirectiveArguments, bodyHTML: String) -> String {
        var css: [String] = []
        if let size = arguments.number("size") { css.append("font-size:\(size)px") }
        if let family = arguments.string("family") { css.append("font-family:\(family)") }
        if arguments.string("weight") == "bold" { css.append("font-weight:bold") }
        return css.isEmpty ? bodyHTML : "<span style=\"\(css.joined(separator: ";"))\">\(bodyHTML)</span>"
    }
}

// MARK: - Shared colour resolution

/// Standard colour names resolved without an asset catalog, so
/// `@color(red){…}` and `@icon(star, color: yellow)` work out of the box. An
/// unlisted name falls back to `NSColor(named:)`, so an embedder's own palette
/// entries keep working.
enum DirectivePalette {
    static let named: [String: NSColor] = [
        "red": .systemRed, "orange": .systemOrange, "yellow": .systemYellow,
        "green": .systemGreen, "mint": .systemMint, "teal": .systemTeal,
        "cyan": .systemCyan, "blue": .systemBlue, "indigo": .systemIndigo,
        "purple": .systemPurple, "pink": .systemPink, "brown": .systemBrown,
        "gray": .systemGray, "grey": .systemGray,
    ]

    static func color(_ name: String) -> NSColor? {
        named[name.lowercased()] ?? NSColor(named: name)
    }
}

// MARK: - @color(red){…}  — container, positional argument

public struct ColorDirective: MarkdownDirective {

    public static let identifier = "color"

    public init() {}

    public var id: String { Self.identifier }

    public var syntax: DirectiveSyntax {
        DirectiveSyntax(
            name: Self.identifier,
            form: .container,
            parameters: [
                // Open set, not closed: the schema can't know the embedder's
                // asset-catalog names, so resolution (and failure) belongs in
                // `style`, not in argument coercion.
                .init(label: nil, kind: .keyword([]), isRequired: true,
                      documentation: "Standard colour name, or a name from your asset catalog."),
            ]
        )
    }

    public var completion: DirectiveCompletion {
        DirectiveCompletion(
            id: id,
            title: "color",
            subtitle: "Tint a span",
            keywords: ["colour", "tint", "foreground"],
            snippet: "@color(|){}",
            symbolName: "paintpalette"
        )
    }

    public func style(arguments: DirectiveArguments, context: DirectiveContext) -> DirectiveStyle {
        guard let name = arguments.positional.first?.asString else { return .inherit }
        // An unresolvable name leaves the body alone rather than guessing —
        // the source stays readable and the mistake is visible.
        guard let color = DirectivePalette.color(name) else { return .inherit }
        return DirectiveStyle(attributes: [.foregroundColor: color])
    }

    public func html(arguments: DirectiveArguments, bodyHTML: String) -> String {
        guard let name = arguments.positional.first?.asString else { return bodyHTML }
        return "<span style=\"color:\(name)\">\(bodyHTML)</span>"
    }
}

// MARK: - @icon(star.fill, color: yellow) — self-contained, glyph from arguments

/// An SF Symbol drawn inline, sized to the surrounding text.
///
/// The counterpart to `@font` for the self-contained form: where a container
/// directive transforms its body, this one replaces its own source with a
/// glyph — and its arguments decide what that glyph is.
public struct IconDirective: MarkdownDirective {

    public static let identifier = "icon"

    public init() {}

    public var id: String { Self.identifier }

    public var syntax: DirectiveSyntax {
        DirectiveSyntax(
            name: Self.identifier,
            form: .selfContained,
            parameters: [
                .init(label: nil, kind: .keyword([]), isRequired: true,
                      documentation: "SF Symbol name, e.g. star.fill."),
                .init(label: "color", kind: .keyword([]),
                      documentation: "Standard colour name, or one from your asset catalog."),
            ]
        )
    }

    public var completion: DirectiveCompletion {
        DirectiveCompletion(
            id: id,
            title: "icon",
            subtitle: "Draw an SF Symbol inline",
            keywords: ["symbol", "glyph", "image"],
            snippet: "@icon(|)",
            symbolName: "star"
        )
    }

    public func presentation(arguments: DirectiveArguments, context: DirectiveContext) -> DirectivePresentation {
        // Revealed source while the caret is inside; an unknown symbol name
        // falls back to the source too, so a typo stays visible and fixable.
        guard !context.isActive, let name = arguments.positional.first?.asString else { return .literal }
        return .symbol(name: name, tint: arguments.string("color").flatMap(DirectivePalette.color))
    }

    /// A curated shortlist, not the full SF Symbols catalogue — the system
    /// ships thousands and exposes no enumeration API. Embedders wanting a
    /// full picker subclass the idea: implement `valueCompletions` against
    /// their own symbol list.
    private static let suggestedSymbols = [
        "star.fill", "star", "heart.fill", "bolt.fill", "flame.fill",
        "checkmark.circle.fill", "xmark.circle.fill", "exclamationmark.triangle.fill",
        "info.circle.fill", "questionmark.circle.fill", "bell.fill", "bookmark.fill",
        "tag.fill", "pin.fill", "paperclip", "link", "calendar", "clock.fill",
        "person.fill", "envelope.fill", "phone.fill", "house.fill", "gearshape.fill",
        "magnifyingglass", "trash.fill", "folder.fill", "doc.fill", "book.fill",
        "lightbulb.fill", "hammer.fill", "wrench.fill", "leaf.fill", "globe",
        "arrow.right", "arrow.up.right", "arrow.down.to.line", "chevron.right",
        "hand.thumbsup.fill", "hand.raised.fill", "eye.fill", "lock.fill",
    ]

    public func valueCompletions(for parameter: DirectiveParameter, prefix: String) -> [DirectiveCompletionItem] {
        // Only the symbol name has an enumerable domain; `color:` falls through
        // to the palette below.
        guard parameter.label == nil else {
            let needle = prefix.lowercased()
            return DirectivePalette.named.keys.sorted()
                .filter { needle.isEmpty || $0.hasPrefix(needle) }
                .map { DirectiveCompletionItem(title: $0, subtitle: "Colour", insertion: $0) }
        }
        let needle = prefix.lowercased()
        return Self.suggestedSymbols
            .filter { needle.isEmpty || $0.hasPrefix(needle) }
            .map { DirectiveCompletionItem(title: $0, subtitle: "SF Symbol",
                                           insertion: $0, symbolName: $0) }
    }

    public func html(arguments: DirectiveArguments, bodyHTML: String) -> String {
        let name = arguments.positional.first?.asString ?? ""
        return "<span class=\"icon\" data-symbol=\"\(name)\"></span>"
    }
}

// MARK: - @flag(JP) — self-contained, VALUE completion

/// A country flag from an ISO region code.
///
/// The reference case for argument-value completion: its domain is far too
/// large to declare as a closed `.keyword` set, so it implements
/// ``MarkdownDirective/valueCompletions(for:prefix:)`` and matches on both the
/// code and the localised country name — type `@flag(jap` and get `JP`.
///
/// Deliberately dataset-free: codes come from `Locale.Region.isoRegions`,
/// names from the user's own locale, and the flag itself is computed from the
/// code's regional-indicator scalars. Nothing to ship, nothing to keep current.
public struct FlagDirective: MarkdownDirective {

    public static let identifier = "flag"

    public init() {}

    public var id: String { Self.identifier }

    public var syntax: DirectiveSyntax {
        DirectiveSyntax(
            name: Self.identifier,
            form: .selfContained,
            parameters: [
                .init(label: nil, kind: .keyword([]), isRequired: true,
                      documentation: "ISO 3166 country code, e.g. JP."),
            ]
        )
    }

    public var completion: DirectiveCompletion {
        DirectiveCompletion(
            id: id,
            title: "flag",
            subtitle: "Country flag from an ISO code",
            keywords: ["country", "nation"],
            snippet: "@flag(|)",
            symbolName: "flag"
        )
    }

    public func presentation(arguments: DirectiveArguments, context: DirectiveContext) -> DirectivePresentation {
        guard !context.isActive,
              let code = arguments.positional.first?.asString,
              let flag = Self.flag(for: code) else { return .literal }
        return .text(flag)
    }

    public func valueCompletions(for parameter: DirectiveParameter, prefix: String) -> [DirectiveCompletionItem] {
        let needle = prefix.lowercased()
        return Self.regions
            .filter { region in
                needle.isEmpty
                    || region.code.lowercased().hasPrefix(needle)
                    || region.name.lowercased().hasPrefix(needle)
            }
            // Code matches first (typing `us` wants US, not "Uruguay"), then
            // alphabetically by name.
            .sorted { a, b in
                let aCode = a.code.lowercased().hasPrefix(needle)
                let bCode = b.code.lowercased().hasPrefix(needle)
                if aCode != bCode { return aCode }
                return a.name < b.name
            }
            .prefix(50)   // the picker is a list, not a gazetteer
            .map { DirectiveCompletionItem(title: $0.code, subtitle: $0.name,
                                           detail: $0.flag, insertion: $0.code) }
    }

    public func html(arguments: DirectiveArguments, bodyHTML: String) -> String {
        guard let code = arguments.positional.first?.asString,
              let flag = Self.flag(for: code) else { return "" }
        return flag
    }

    // MARK: Regions

    struct Region {
        let code: String
        let name: String
        let flag: String
    }

    /// Two-letter regions that have a flag, named in the user's locale.
    /// Built once — `isoRegions` is a few hundred entries and the localised
    /// lookups are the expensive part.
    static let regions: [Region] = {
        Locale.Region.isoRegions.compactMap { region in
            let code = region.identifier
            guard code.count == 2, let flag = flag(for: code) else { return nil }
            let name = Locale.current.localizedString(forRegionCode: code) ?? code
            return Region(code: code, name: name, flag: flag)
        }
    }()

    /// Regional-indicator scalars: `JP` → 🇯🇵.
    static func flag(for code: String) -> String? {
        let upper = code.uppercased()
        guard upper.count == 2 else { return nil }
        var scalars = String.UnicodeScalarView()
        for scalar in upper.unicodeScalars {
            guard scalar.value >= 0x41, scalar.value <= 0x5A,
                  let indicator = UnicodeScalar(0x1F1E6 + scalar.value - 0x41) else { return nil }
            scalars.append(indicator)
        }
        return String(scalars)
    }
}

// MARK: - @pagebreak — self-contained

public struct PageBreakDirective: MarkdownDirective {

    public static let identifier = "pagebreak"

    public init() {}

    public var id: String { Self.identifier }

    public var syntax: DirectiveSyntax {
        DirectiveSyntax(name: Self.identifier, form: .selfContained)
    }

    public var completion: DirectiveCompletion {
        DirectiveCompletion(
            id: id,
            title: "pagebreak",
            subtitle: "Force a page break when printing",
            keywords: ["page", "break", "print"],
            snippet: "@pagebreak",
            symbolName: "arrow.down.to.line"
        )
    }

    public func presentation(arguments: DirectiveArguments, context: DirectiveContext) -> DirectivePresentation {
        // While the caret is inside, the source stays visible — the engine
        // handles that flip; the directive just declines the glyph.
        context.isActive ? .literal : .symbol(name: "arrow.down.to.line", tint: context.theme.mutedText)
    }

    public func html(arguments: DirectiveArguments, bodyHTML: String) -> String {
        "<hr class=\"pagebreak\" />"
    }
}
