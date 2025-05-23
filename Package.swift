// swift-tools-version:6.0
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
        )
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(name: "_JSONCore"),
        .target(
            name: "_NIOJSON",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .target(name: "_JSONCore"),
            ]
        ),
        .target(
            name: "IkigaJSON",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .target(name: "_JSONCore"),
                .target(name: "_NIOJSON"),
            ]
        ),
        .testTarget(
            name: "IkigaJSONTests",
            dependencies: [.target(name: "IkigaJSON")]),
    ]
)
