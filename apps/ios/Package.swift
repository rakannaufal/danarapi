// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DanarapiContracts",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DanarapiContracts", targets: ["DanarapiContracts"])
    ],
    targets: [
        .target(name: "DanarapiContracts"),
        .testTarget(name: "DanarapiContractsTests", dependencies: ["DanarapiContracts"])
    ]
)

