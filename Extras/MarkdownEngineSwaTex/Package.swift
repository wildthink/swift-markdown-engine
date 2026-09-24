// swift-tools-version: 6.1
import PackageDescription

// MarkdownEngineSwaTex — opt-in `LatexRenderer` backed by SwaTex, a pure-Swift
// KaTeX-compatible math engine (no WebView, no JavaScript).
//
// This is a separate package, not a product of the root `Package.swift`, on
// purpose: SwaTex requires macOS 15 / Swift 6.1, and SwiftPM applies a
// dependency's platform floor to the whole package. Putting it in the root
// manifest would raise the engine's floor from macOS 14 for every embedder,
// including the ones who never link it.
let package = Package(
    name: "MarkdownEngineSwaTex",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MarkdownEngineSwaTex", targets: ["MarkdownEngineSwaTex"]),
    ],
    dependencies: [
        .package(name: "swift-markdown-engine", path: "../.."),
        .package(url: "https://github.com/PhraseHQ/SwaTex.git", from: "0.5.0"),
    ],
    targets: [
        .target(
            name: "MarkdownEngineSwaTex",
            dependencies: [
                .product(name: "MarkdownEngine", package: "swift-markdown-engine"),
                .product(name: "SwaTexRender", package: "SwaTex"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MarkdownEngineSwaTexTests",
            dependencies: [
                "MarkdownEngineSwaTex",
                .product(name: "MarkdownEngine", package: "swift-markdown-engine"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
