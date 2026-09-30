//
//  SwaTexBridgeTests.swift
//  MarkdownEngineSwaTexTests
//

import AppKit
import Testing
import MarkdownEngine
import MarkdownEngineSwaTex

@MainActor
@Suite("SwaTexBridge", .serialized)
struct SwaTexBridgeTests {
    private let bridge = SwaTexBridge()

    private func render(_ latex: String, _ mode: LatexRenderMode = .inline) -> LatexRenderResult? {
        _ = NSApplication.shared
        return bridge.render(latex: latex, mode: mode, fontSize: 20, theme: .default)
    }

    @Test("Renders a formula to a non-empty image")
    func renders() throws {
        let r = try #require(render(#"\frac{-b \pm \sqrt{b^2-4ac}}{2a}"#))
        #expect(r.size.width > 0 && r.size.height > 0)
        #expect(r.image.size == r.size)
    }

    @Test("Display mode typesets taller than inline")
    func displayMode() throws {
        let latex = #"\sum_{i=1}^{n} x_i"#
        let inline = try #require(render(latex, .inline))
        let display = try #require(render(latex, .display))
        #expect(display.size.height > inline.size.height)
    }

    @Test("Baseline offset lies within the image")
    func baseline() throws {
        let r = try #require(render(#"x_{i}^{2}"#))
        #expect(r.baselineOffset >= 0 && r.baselineOffset < r.size.height)
    }

    @Test("A descender-free formula sits on its baseline; a subscript hangs below it")
    func baselineTracksDescent() throws {
        let flat = try #require(render("x"))
        let sub = try #require(render("x_{i}"))
        #expect(flat.baselineOffset == 0)
        #expect(sub.baselineOffset > 0)
    }

    @Test("Unparseable input returns nil so the engine falls back to source text")
    func failure() {
        #expect(render(#"\frac{a}{"#) == nil)
        #expect(render(#"\badcommand{x}"#) == nil)
        #expect(render("   ") == nil)
    }

    @Test("Chemistry (mhchem) renders")
    func chemistry() {
        #expect(render(#"\ce{H2SO4 + 2NaOH -> Na2SO4 + 2H2O}"#) != nil)
    }

    @Test("Repeated renders are served from the cache")
    func cached() throws {
        let a = try #require(render(#"a^2+b^2=c^2"#))
        let b = try #require(render(#"a^2+b^2=c^2"#))
        #expect(a.image === b.image)
        bridge.clearCache()
        let c = try #require(render(#"a^2+b^2=c^2"#))
        #expect(a.image !== c.image)
    }

    @Test("Rapid valid and malformed edits never reuse a stale rendered result")
    func rapidChangingInput() {
        for index in 0..<100 {
            #expect(render("x_{\(index)}^2") != nil)
            #expect(render(#"\frac{a}{"#) == nil)
        }
    }

    @Test("Five hundred distinct equations render for the scrolling stress fixture")
    func fiveHundredEquationStressFixture() {
        var rendered = 0
        for index in 0..<500 {
            if render("x_{\(index)}^2 + y_{\(index)}^2 = z_{\(index)}^2") != nil {
                rendered += 1
            }
        }
        #expect(rendered == 500)
    }
}
