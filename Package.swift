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
        // llama.cpp official repository (Latest master for LFM/Llama3 support)
        .package(url: "https://github.com/ggml-org/llama.cpp.git", branch: "master")
    ],
    targets: [
        .target(
            name: "EliAI",
            dependencies: [
                .product(name: "llama", package: "llama.cpp")
            ],
            swiftSettings: [.interoperabilityMode(.Cxx)])
    ]
)
