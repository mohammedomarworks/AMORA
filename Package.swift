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
    targets: [
        .executableTarget(
            name: "AMORA",
            dependencies: [],
            path: "Sources/AMORA"
        ),
        .executableTarget(
            name: "AMORA-BrowserHost",
            dependencies: [],
            path: "Sources/AMORABrowserHost"
        ),
        .testTarget(
            name: "AMORATests",
            dependencies: ["AMORA"],
            path: "Tests/AMORATests"
        ),
    ]
)
