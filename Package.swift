// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ImageProcessingKit",
    platforms: [
        .macOS(.v15),
        .iOS(.v16),
        .tvOS(.v18)
    ],
    products: [
        .library(
            name: "ImageProcessingKit",
            targets: ["ImageProcessingKit"]
        ),
    ],
    dependencies: [
        .package(path: "../LoggingKit"),
    ],
    targets: [
        .target(
            name: "ImageProcessingKit",
            dependencies: ["LoggingKit"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "ImageProcessingKitTests",
            dependencies: ["ImageProcessingKit"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
