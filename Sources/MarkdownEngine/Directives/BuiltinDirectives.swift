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

    public func html(arguments: DirectiveArguments, bodyHTML: String) -> String {
        let name = arguments.positional.first?.asString ?? ""
        return "<span class=\"icon\" data-symbol=\"\(name)\"></span>"
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
