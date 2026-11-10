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
        .library(name: "PadelStats", targets: ["PadelStats"]),
    ],
    targets: [
        // Scoring rules of a single match (watch).
        .target(name: "PadelScoring"),
        // Match summaries exchanged between watch and iPhone, plus all statistics.
        .target(name: "PadelStats", dependencies: ["PadelScoring"]),
        .testTarget(name: "PadelScoringTests", dependencies: ["PadelScoring"]),
        .testTarget(name: "PadelStatsTests", dependencies: ["PadelStats"]),
    ]
)
