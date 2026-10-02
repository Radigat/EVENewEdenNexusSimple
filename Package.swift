// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "EVENexusSimple",
  defaultLocalization: "en",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "EVENexusCore", targets: ["EVENexusCore"]),
    .executable(name: "EVE Nexus Simple", targets: ["EVENexusSimpleApp"]),
    .executable(
      name: "EVENexusLiveAcceptance",
      targets: ["EVENexusLiveAcceptance"]
    ),
  ],
  dependencies: [
    .package(path: "Packages/EVEStaticDataKit")
  ],
  targets: [
    .systemLibrary(name: "CSQLite"),
    .target(
      name: "EVENexusCore",
      dependencies: [
        "CSQLite",
        .product(name: "EVEStaticDataKit", package: "EVEStaticDataKit"),
      ]
    ),
    .executableTarget(
      name: "EVENexusSimpleApp",
      dependencies: ["EVENexusCore"],
      resources: [.process("Resources")]
    ),
    .executableTarget(
      name: "EVENexusLiveAcceptance",
      dependencies: ["EVENexusCore"]
    ),
    .testTarget(
      name: "EVENexusCoreTests",
      dependencies: [
        "EVENexusCore",
        "CSQLite",
        .product(name: "EVEStaticDataKit", package: "EVEStaticDataKit"),
      ]
    ),
  ]
)
