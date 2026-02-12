// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "EliAI",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "EliAI",
            targets: ["EliAI"]),
    ],
    dependencies: [
        // State-of-the-Art 2026 LLM Wrapper (Local Patch Path)
        .package(path: "Packages/LLM"),
        // SwiftSyntax for 2026 Macros (Aligned with LLM.swift 600.0.1)
        .package(url: "https://github.com/apple/swift-syntax.git", from: "600.0.1")
    ],
    targets: [
        .target(
            name: "EliAI",
            dependencies: [
                .product(name: "LLM", package: "LLM")
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
                .enableExperimentalFeature("Macros")
            ])
    ]
)
