// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TillyCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TillyCore", targets: ["TillyCore"]),
    ],
    targets: [
        .target(name: "TillyCore"),
        .testTarget(name: "TillyCoreTests", dependencies: ["TillyCore"]),
    ]
)
