// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GoldAlert",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        // xtool expects exactly one library product = the main app.
        .library(
            name: "GoldAlert",
            targets: ["GoldAlert"]
        ),
    ],
    targets: [
        .target(
            name: "GoldAlert"
        ),
    ]
)
