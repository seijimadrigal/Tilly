// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TillyProviders",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TillyProviders", targets: ["TillyProviders"]),
    ],
    dependencies: [
        .package(path: "../TillyCore"),
    ],
    targets: [
        .target(name: "TillyProviders", dependencies: ["TillyCore"]),
        .testTarget(name: "TillyProvidersTests", dependencies: ["TillyProviders"]),
    ]
)
