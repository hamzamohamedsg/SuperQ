// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SuperQ",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SuperQ", targets: ["SuperQ"])
    ],
    targets: [
        .executableTarget(
            name: "SuperQ",
            path: "Sources/SuperQ"
        )
    ]
)
