// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Legenda",
    platforms: [.macOS(.v14)],
    targets: [
        // Thin launcher. Everything real lives in LegendaCore so that the test
        // target can link against it without colliding with `main`.
        .executableTarget(
            name: "Legenda",
            dependencies: ["LegendaCore"],
            path: "Sources/Legenda"
        ),
        .target(
            name: "LegendaCore",
            path: "Sources/LegendaCore"
        ),
        .testTarget(
            name: "LegendaCoreTests",
            dependencies: ["LegendaCore"],
            path: "Tests/LegendaCoreTests"
        ),
    ]
)
