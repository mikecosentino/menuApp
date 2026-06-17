// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "menuApp",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "menuApp",
            path: "Sources/menuApp"
        )
    ]
)
