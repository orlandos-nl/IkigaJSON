// swift-tools-version:6.0
import PackageDescription

let package = Package(
  name: "JSONBenchmark",
  platforms: [
    .macOS(.v14)
  ],
  dependencies: [
    .package(path: "../.."),
    .package(url: "https://github.com/ordo-one/package-benchmark", from: "1.27.0"),
  ],
  targets: [
    .executableTarget(
      name: "JSONBenchmark",
      dependencies: [
        .product(name: "IkigaJSON", package: "IkigaJSON"),
        .product(name: "Benchmark", package: "package-benchmark"),
      ],
      path: ".",
      exclude: ["Package.swift"],
      plugins: [
        .plugin(name: "BenchmarkPlugin", package: "package-benchmark")
      ]
    )
  ]
)
