// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PipePlayer",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "PipePlayer",
            path: "Sources/PipePlayer"
        ),
        .testTarget(
            name: "PipePlayerTests",
            dependencies: ["PipePlayer"],
            path: "Tests/PipePlayerTests"
        )
    ]
)
