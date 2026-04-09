// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TillyTools",
    platforms: [.macOS(.v15), .iOS(.v17)],
    products: [
        .library(name: "TillyTools", targets: ["TillyTools"]),
    ],
    dependencies: [
        .package(path: "../TillyCore"),
        .package(path: "../TillyStorage"),
    ],
    targets: [
        .target(name: "TillyTools", dependencies: ["TillyCore", "TillyStorage"]),
        .testTarget(name: "TillyToolsTests", dependencies: ["TillyTools"]),
    ]
)
