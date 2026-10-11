// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AMORA",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "AMORA",
            targets: ["AMORA"]
        ),
        .executable(
            name: "AMORA-BrowserHost",
            targets: ["AMORA-BrowserHost"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/mattt/llama.swift", exact: "2.10549.0")
    ],
    targets: [
        .executableTarget(
            name: "AMORA",
            dependencies: [
                .product(name: "LlamaSwift", package: "llama.swift")
            ],
            path: "Sources/AMORA",
            swiftSettings: [
                .unsafeFlags([
                    "-F", ".build/artifacts/llama.swift/llama-cpp/llama.xcframework/macos-arm64_x86_64",
                    "-F", ".build/index-build/artifacts/llama.swift/llama-cpp/llama.xcframework/macos-arm64_x86_64"
                ])
            ]
        ),
        .executableTarget(
            name: "AMORA-BrowserHost",
            dependencies: [],
            path: "Sources/AMORABrowserHost"
        ),
        .testTarget(
            name: "AMORATests",
            dependencies: [
                "AMORA",
                .product(name: "LlamaSwift", package: "llama.swift")
            ],
            path: "Tests/AMORATests",
            swiftSettings: [
                .unsafeFlags([
                    "-F", ".build/artifacts/llama.swift/llama-cpp/llama.xcframework/macos-arm64_x86_64",
                    "-F", ".build/index-build/artifacts/llama.swift/llama-cpp/llama.xcframework/macos-arm64_x86_64"
                ])
            ]
        ),
    ]
)
