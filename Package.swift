// swift-tools-version:6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "IkigaJSON",
  platforms: [
    .iOS(.v12),
    .macOS(.v10_15),
  ],
  products: [
    // Products define the executables and libraries produced by a package, and make them visible to other packages.
    .library(
      name: "IkigaJSON",
      targets: ["IkigaJSON"]
    ),
    // Embedded Swift compatible library - no Foundation or NIO dependencies
    .library(
      name: "IkigaJSONCore",
      targets: ["_JSONCore"]
    ),
  ],
  traits: [
    .trait(name: "FoundationSupport"),
    .default(enabledTraits: ["FoundationSupport"]),
  ],
  dependencies: [
    // Dependencies declare other packages that this package depends on.
    .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0")
  ],
  targets: [
    // Targets are the basic building blocks of a package. A target can define a module or a test suite.
    // Targets can depend on other targets in this package, and on products in packages which this package depends on.
    .target(
      name: "_JSONCore",
      swiftSettings: [
        // Enable strict concurrency for Embedded Swift compatibility
        .enableExperimentalFeature("StrictConcurrency"),
        .enableExperimentalFeature("Lifetimes"),
      ]
    ),
    .target(
      name: "_NIOJSON",
      dependencies: [
        .product(name: "NIOCore", package: "swift-nio", condition: .when(traits: ["FoundationSupport"])),
        .product(name: "NIOFoundationCompat", package: "swift-nio", condition: .when(traits: ["FoundationSupport"])),
        .target(name: "_JSONCore"),
      ]
    ),
    .target(
      name: "IkigaJSON",
      dependencies: [
        .product(name: "NIOCore", package: "swift-nio", condition: .when(traits: ["FoundationSupport"])),
        .target(name: "_JSONCore"),
        .target(name: "_NIOJSON", condition: .when(traits: ["FoundationSupport"])),
      ],
      swiftSettings: [
        .define("FOUNDATION_SUPPORT", .when(traits: ["FoundationSupport"])),
      ]
    ),
    .testTarget(
      name: "IkigaJSONTests",
      dependencies: [.target(name: "IkigaJSON")]),
  ]
)
