// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Dangle",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DangleKit"),
        .executableTarget(
            name: "DangleApp",
            dependencies: ["DangleKit"]
        ),
        .executableTarget(
            name: "DangleSnapshot",
            dependencies: ["DangleKit"]
        ),
        .testTarget(
            name: "DangleKitTests",
            dependencies: ["DangleKit"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
