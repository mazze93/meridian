// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Meridian",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "MeridianCore", targets: ["MeridianCore"]),
        .library(name: "MeridianUI", targets: ["MeridianUI"]),
        .library(name: "MeridianApp", targets: ["MeridianApp"]),
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
        .target(
            name: "MeridianUI",
            dependencies: ["MeridianCore"]
        ),
        .target(
            name: "MeridianApp",
            dependencies: ["MeridianUI"]
        ),
        .testTarget(
            name: "MeridianCoreTests",
            dependencies: ["MeridianCore"]
        ),
        .testTarget(
            name: "MeridianUITests",
            dependencies: ["MeridianUI", "MeridianCore"]
        ),
    ]
)
