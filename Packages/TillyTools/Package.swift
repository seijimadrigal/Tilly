// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TillyTools",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TillyTools", targets: ["TillyTools"]),
    ],
    dependencies: [
        .package(path: "../TillyCore"),
    ],
    targets: [
        .target(name: "TillyTools", dependencies: ["TillyCore"]),
        .testTarget(name: "TillyToolsTests", dependencies: ["TillyTools"]),
    ]
)
