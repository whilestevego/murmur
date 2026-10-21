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
    .executableTarget(name: "murmurd", dependencies: ["MurmurCore", "ObjCTry", "FluidAudio"]),
    // Pure logic shared by both and unit-tested: protocol, paths, sentence splitting, cache keys.
    .target(name: "MurmurCore"),
    // Catches the Objective-C exceptions AVAudioEngine raises, which Swift can't.
    .target(name: "ObjCTry"),
    .testTarget(name: "MurmurCoreTests", dependencies: ["MurmurCore", "ObjCTry"]),
  ],
  swiftLanguageModes: [.v6]
)
