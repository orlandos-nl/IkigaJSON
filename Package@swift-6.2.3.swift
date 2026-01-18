// swift-tools-version:6.2.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let strictMemorySafetySettings: [SwiftSetting] = [
  .enableExperimentalFeature("LifetimeDependence"),
  .enableExperimentalFeature("Lifetimes"),
  .strictMemorySafety(),
]

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
    )
  ],
  traits: [
    .default(enabledTraits: ["ByteBufferSupport", "FoundationSupport"]),
    .trait(name: "Spans"),
    .trait(name: "SourcePositions"),
    .trait(name: "ByteBufferSupport"),
    .trait(name: "FoundationSupport"),
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
      swiftSettings: strictMemorySafetySettings
    ),
    .target(
      name: "_NIOJSON",
      dependencies: [
        .product(
          name: "NIOCore", package: "swift-nio", condition: .when(traits: ["ByteBufferSupport"])),
        .product(
          name: "NIOFoundationCompat", package: "swift-nio",
          condition: .when(traits: ["ByteBufferSupport"])),
        .target(name: "_JSONCore"),
      ],
      swiftSettings: strictMemorySafetySettings
    ),
    .target(
      name: "IkigaJSON",
      dependencies: [
        .product(name: "NIOCore", package: "swift-nio"),
        .target(name: "_JSONCore"),
        .target(name: "_NIOJSON"),
      ],
      swiftSettings: strictMemorySafetySettings
    ),
    .testTarget(
      name: "IkigaJSONTests",
      dependencies: [.target(name: "IkigaJSON")],
      swiftSettings: strictMemorySafetySettings
    ),
  ]
)
