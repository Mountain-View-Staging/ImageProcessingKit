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
        .package(url: "https://github.com/Mountain-View-Staging/LoggingKit.git", from: "1.0.0"),
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
