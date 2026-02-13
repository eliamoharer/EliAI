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
        ),
        .package(
            url: "https://github.com/mgriebling/SwiftMath.git",
            revision: "fa8244ed032f4a1ade4cb0571bf87d2f1a9fd2d7"
        )
    ],
    targets: [
        .target(
            name: "EliAI",
            path: "EliAI/EliAI",
            dependencies: [
                .product(name: "LLM", package: "LLM"),
                .product(name: "SwiftMath", package: "SwiftMath")
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ])
    ]
)
