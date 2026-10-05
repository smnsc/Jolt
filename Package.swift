// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "Jolt",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "JoltCore", targets: ["JoltCore"]),
    .executable(name: "Jolt", targets: ["JoltApp"]),
  ],
  dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
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
      dependencies: ["JoltCore", .product(name: "Sparkle", package: "Sparkle")],
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("Carbon"),
        .linkedFramework("Security"),
        .linkedFramework("ServiceManagement"),
        .linkedFramework("SwiftUI"),
        .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
      ]
    ),
    .testTarget(
      name: "JoltCoreTests",
      dependencies: ["JoltCore"]
    ),
  ],
  swiftLanguageModes: [.v5]
)
