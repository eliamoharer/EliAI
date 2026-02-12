// swift-tools-version: 6.0
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "LLM",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "LLM", targets: ["LLM"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", from: "600.0.1"),
    ],
    targets: [
        .target(
            name: "LLM",
            dependencies: [
                "llama",
                "LLMMacrosImplementation",
            ],
            path: "Sources/LLM"
        ),
        .binaryTarget(
            name: "llama",
            path: "llama.cpp/llama.xcframework"
        ),
        .macro(
            name: "LLMMacrosImplementation",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ]
        )
    ]
)
