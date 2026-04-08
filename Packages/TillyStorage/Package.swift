// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TillyStorage",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TillyStorage", targets: ["TillyStorage"]),
    ],
    dependencies: [
        .package(path: "../TillyCore"),
    ],
    targets: [
        .target(name: "TillyStorage", dependencies: ["TillyCore"]),
        .testTarget(name: "TillyStorageTests", dependencies: ["TillyStorage"]),
    ]
)
