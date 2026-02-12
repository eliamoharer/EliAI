// swift-tools-version: 6.0
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
        .package(
            url: "https://github.com/eastriverlee/LLM.swift.git",
            revision: "4c4e909ac4758c628c9cd263a0c25b6edff5526d"
        )
    ],
    targets: [
        .target(
            name: "EliAI",
            path: "EliAI/EliAI",
            dependencies: [
                .product(name: "LLM", package: "LLM")
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
                .enableExperimentalFeature("Macros")
            ])
    ]
)
