//
//  SwaTexBridge.swift
//  MarkdownEngineSwaTex
//
//  Spike: LatexRenderer conformance backed by SwaTex (pure-Swift KaTeX engine).
//

import AppKit
import Foundation
import SwaTex
import SwaTexRender
import MarkdownEngine

public final class SwaTexBridge: LatexRenderer, @unchecked Sendable {
    private struct CacheKey: Hashable {
        let latex: String
        let mode: LatexRenderMode
        let fontSize: CGFloat
        let color: SwaTex.Color
        let scale: CGFloat
    }

    private var cache: [CacheKey: LatexRenderResult] = [:]
    private let lock = NSLock()

    public init() {}

    public func clearCache() {
        lock.lock(); cache.removeAll(); lock.unlock()
    }

    public func render(latex: String, fontSize: CGFloat, theme: MarkdownEditorTheme) -> LatexRenderResult? {
        render(latex: latex, mode: .inline, fontSize: fontSize, theme: theme)
    }

    public func render(
        latex: String, mode: LatexRenderMode, fontSize: CGFloat, theme: MarkdownEditorTheme
    ) -> LatexRenderResult? {
        let normalized = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        let appearance = NSApp?.keyWindow?.effectiveAppearance ?? NSApp?.effectiveAppearance
        let isDark = appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let color = Self.swaColor(isDark ? theme.latexDarkModeText : theme.latexLightModeText)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let key = CacheKey(latex: normalized, mode: mode, fontSize: fontSize, color: color, scale: scale)

        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()

        let style: MathStyle = mode == .display ? .display : .text
        // A ParseError means "cannot render": the engine falls back to source text.
        guard let list = try? SwaTexEngine.displayList(for: normalized, style: style, color: color, cache: .shared)
        else { return nil }

        let options = RenderOptions(fontSize: fontSize, padding: 0)
        let m = DisplayListRenderer.metrics(for: list, options: options)
        guard m.width > 1 || m.height > 1,
              let cg = ImageRenderer.image(for: list, options: options, displayScale: scale)
        else { return nil }

        let size = CGSize(width: m.width, height: m.height)
        let image = NSImage(cgImage: cg, size: size)
        let result = LatexRenderResult(
            image: image, size: size, baselineOffset: max(m.height - m.baseline, 0))

        lock.lock(); cache[key] = result; lock.unlock()
        return result
    }

    private static func swaColor(_ c: NSColor) -> SwaTex.Color {
        guard let rgb = c.usingColorSpace(.sRGB) else { return .black }
        return SwaTex.Color(
            r: Float(rgb.redComponent), g: Float(rgb.greenComponent),
            b: Float(rgb.blueComponent), a: Float(rgb.alphaComponent))
    }
}
