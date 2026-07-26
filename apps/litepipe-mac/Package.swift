// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "litepipe",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "litepipe",
            path: "Sources/litepipe"
        )
    ]
)
