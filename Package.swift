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
        // llama.cpp swift wrapper
        .package(url: "https://github.com/srgtuszy/llama-cpp-swift", branch: "main")
    ],
    targets: [
        .target(
            name: "EliAI",
            dependencies: [
                .product(name: "llama-cpp-swift", package: "llama-cpp-swift")
            ])
    ]
)
