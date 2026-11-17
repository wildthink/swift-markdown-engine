//
//  LinkIcon.swift
//  MarkdownEngine
//
//  The icon drawn before a hidden link's text (`MarkdownEditorServices.linkIcons`).
//  Drawing only: the styler kerns the link's collapsed `[` to leave room and
//  `MarkdownTextLayoutFragment` paints the image there. The text never changes.
//

import AppKit

extension NSAttributedString.Key {
    /// NSImage — the icon painted in front of a link. Set on the link's opening `[` only.
    static let linkIcon = NSAttributedString.Key("MarkdownLinkIcon")
    /// NSValue(rect:) — the icon's size, and in `origin.y` how far its bottom sits below the baseline.
    static let linkIconBounds = NSAttributedString.Key("MarkdownLinkIconBounds")
}

/// Size and placement of a link icon for the text it sits in.
struct LinkIconGeometry {
    /// Square side: a little under the font's point size, so it sits inside the line like a glyph.
    let side: CGFloat
    /// Space between the icon and the link text.
    let gap: CGFloat
    /// How far the icon's bottom sits below the baseline: centred on the x-height, as symbols are.
    let descent: CGFloat

    init(font: NSFont) {
        side = (font.pointSize * 0.9).rounded()
        gap = max(2, (font.pointSize * 0.25).rounded())
        descent = (side - font.xHeight) / 2
    }

    /// Room the icon takes on the line.
    var advance: CGFloat { side + gap }

    var bounds: CGRect { CGRect(x: 0, y: descent, width: side, height: side) }

    /// A one-colour (template) icon in `color`, resolved when drawn so it follows light/dark.
    static func tinted(_ image: NSImage, with color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}
