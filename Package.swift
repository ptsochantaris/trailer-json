// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "TrailerJson",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v14),
        .watchOS(.v4)
    ],
    products: [
        .library(
            name: "TrailerJson",
            targets: ["TrailerJson"]
        )
    ],
    dependencies: [
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
