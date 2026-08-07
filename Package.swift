// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LightTable",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "LightTable",
            path: "Sources/LightTable"
        )
    ]
)
