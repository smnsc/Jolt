// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "Jolt",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "JoltCore", targets: ["JoltCore"]),
    .executable(name: "Jolt", targets: ["JoltApp"]),
  ],
  targets: [
    .target(
      name: "JoltCore",
      linkerSettings: [
        .linkedFramework("Security")
      ]
    ),
    .executableTarget(
      name: "JoltApp",
      dependencies: ["JoltCore"],
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("Carbon"),
        .linkedFramework("Security"),
        .linkedFramework("ServiceManagement"),
        .linkedFramework("SwiftUI"),
      ]
    ),
    .testTarget(
      name: "JoltCoreTests",
      dependencies: ["JoltCore"]
    ),
  ],
  swiftLanguageModes: [.v5]
)
