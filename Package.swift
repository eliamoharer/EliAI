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
        // Modern llama.cpp wrapper (v8.0.4+)
        .package(url: "https://github.com/mattt/llama.swift", branch: "main")
    ],
    targets: [
        .target(
            name: "EliAI",
            dependencies: [
                .product(name: "LlamaSwift", package: "llama.swift")
            ],
            swiftSettings: [.interoperabilityMode(.Cxx)])
    ]
)
