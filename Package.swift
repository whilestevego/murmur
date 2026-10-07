// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "murmur",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "murmur", targets: ["murmur"]),
    .executable(name: "murmurd", targets: ["murmurd"]),
  ],
  dependencies: [
    .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.15.5")
  ],
  targets: [
    // The client links nothing heavy: it starts in milliseconds and only hands text to murmurd.
    .executableTarget(name: "murmur", dependencies: ["MurmurCore"]),
    .executableTarget(name: "murmurd", dependencies: ["MurmurCore", "FluidAudio"]),
    // Pure logic shared by both and unit-tested: protocol, paths, sentence splitting, cache keys.
    .target(name: "MurmurCore"),
    .testTarget(name: "MurmurCoreTests", dependencies: ["MurmurCore"]),
  ],
  swiftLanguageModes: [.v5]
)
