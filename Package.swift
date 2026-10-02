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
    ],
    targets: [
        .executableTarget(
            name: "AMORA",
            dependencies: [],
            path: "Sources/AMORA"
        ),
        .testTarget(
            name: "AMORATests",
            dependencies: ["AMORA"],
            path: "Tests/AMORATests"
        ),
    ]
)
