// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TychoCompanion",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TychoCompanionKit", targets: ["TychoCompanionKit"]),
        .executable(name: "TychoCompanion", targets: ["TychoCompanion"])
    ],
    targets: [
        .target(name: "TychoCompanionKit"),
        .executableTarget(name: "TychoCompanion", dependencies: ["TychoCompanionKit"]),
        .testTarget(name: "TychoCompanionKitTests", dependencies: ["TychoCompanionKit"])
    ]
)
