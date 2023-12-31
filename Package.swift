// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "TrailerJson",
    platforms: [
        .macOS(.v11),
        .iOS(.v14),
        .watchOS(.v7)
    ],
    products: [
        .library(
            name: "TrailerJson",
            targets: ["TrailerJson"]
        )
    ],
    targets: [
        .target(name: "TrailerJson"),

        .testTarget(name: "TrailerJsonTests",
                    dependencies: ["TrailerJson"],
                    resources: [.copy("10mb.json")]),

        .executableTarget(name: "Benchmark",
                          dependencies: ["TrailerJson"],
                          resources: [.copy("10mb.json")])
    ]
)
