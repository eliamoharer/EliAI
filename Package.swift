// swift-tools-version: 5.9
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
        // State-of-the-Art 2026 LLM Wrapper
        .package(url: "https://github.com/eastriverlee/LLM.swift", branch: "main")
    ],
    targets: [
        .target(
            name: "EliAI",
            dependencies: [
                .product(name: "LLM", package: "LLM.swift")
            ],
            swiftSettings: [.interoperabilityMode(.Cxx)])
    ]
)
