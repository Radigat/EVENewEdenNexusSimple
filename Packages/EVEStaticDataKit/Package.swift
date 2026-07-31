// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EVEStaticDataKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "EVEStaticDataKit",
            targets: ["EVEStaticDataKit"]
        )
    ],
    targets: [
        .target(name: "EVEStaticDataKit"),
        .testTarget(
            name: "EVEStaticDataKitTests",
            dependencies: ["EVEStaticDataKit"]
        )
    ]
)
