// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "PhotosClone",
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(name: "PhotosClone", path: "Sources/PhotosClone")
    ]
)
