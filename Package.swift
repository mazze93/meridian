// swift-tools-version: 5.9
import PackageDescription

// MeridianUI and MeridianApp targets are introduced at Layer 2, when they gain sources.
// SPM cannot build a target with an empty source directory, and CLAUDE.md forbids stubs,
// so the manifest declares only the targets that currently have real code.
let package = Package(
    name: "Meridian",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "MeridianCore", targets: ["MeridianCore"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/automerge/automerge-swift",
            from: "0.7.2"
        ),
    ],
    targets: [
        .target(
            name: "MeridianCore",
            dependencies: [
                .product(name: "Automerge", package: "automerge-swift"),
            ]
        ),
        .testTarget(
            name: "MeridianCoreTests",
            dependencies: ["MeridianCore"]
        ),
    ]
)
