// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "litepipe",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "litepipe",
            path: "Sources/litepipe",
            linkerSettings: [
                .linkedLibrary("sqlite3") // read the engine's ~/.litepipe/db.sqlite
            ]
        ),
        // The bridge an agent connects through, as a second executable rather than
        // a mode of the first: MCP clients spawn a process and talk to it over
        // stdin, which an app that owns a window cannot be. It shares the window's
        // reader by symlink, so the agent and the timeline answer alike.
        .executableTarget(
            name: "litepipe-mcp",
            path: "Sources/litepipe-mcp",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
