# MarkdownEngineSwaTex

`MarkdownEngineSwaTex` is the recommended opt-in LaTeX renderer for
MarkdownEngine applications targeting macOS 15 or newer. It adapts
[SwaTex 0.5.0](https://github.com/PhraseHQ/SwaTex/tree/0.5.0) to the editor's
`LatexRenderer` service using SwaTex's native CoreGraphics renderer.

The integration keeps `$…$` and `$$…$$` source in the document. Rendered
images are disposable presentation state: moving the caret into a formula or
selecting through it reveals the literal source, and malformed or incomplete
LaTeX remains visible and editable.

## Requirements

- macOS 15 or newer
- Swift 6.1 or newer
- SwaTex exactly 0.5.0

The bridge is a separate package so the main MarkdownEngine package can retain
its macOS 14 deployment target and zero-dependency core.

## Add the package

For a checkout of this repository:

```swift
dependencies: [
    .package(path: "path/to/swift-markdown-engine/Extras/MarkdownEngineSwaTex"),
]
```

Add the product to the application target:

```swift
dependencies: [
    .product(name: "MarkdownEngineSwaTex", package: "MarkdownEngineSwaTex"),
]
```

Then install it in the editor configuration:

```swift
import MarkdownEngine
import MarkdownEngineSwaTex

var configuration = MarkdownEditorConfiguration.default
configuration.services = MarkdownEditorServices(latex: SwaTexBridge())
```

No SwaTex AST or display list is persisted. `SwaTexBridge.clearCache()` drops
only the bridge's raster-image cache; SwaTex manages its shared parse/layout
cache independently.

## Verify

From this directory:

```sh
swift test
```

The package tests cover inline and display rendering, baseline metrics,
malformed-input fallback, mhchem, caching, rapid source changes, and a fixture
of 500 distinct equations. TextKit caret, selection, editing, clipboard,
undo/redo, and scrolling behavior is covered by the root package's
`LatexRenderModeTests` suite.
