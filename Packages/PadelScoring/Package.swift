// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PadelScoring",
    platforms: [
        .watchOS(.v10),
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "PadelScoring", targets: ["PadelScoring"]),
    ],
    targets: [
        .target(name: "PadelScoring"),
        .testTarget(name: "PadelScoringTests", dependencies: ["PadelScoring"]),
    ]
)
