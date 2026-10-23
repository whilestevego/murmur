// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "murmur",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "murmur", targets: ["murmur"]),
    .executable(name: "murmurd", targets: ["murmurd"]),
  ],
  dependencies: [
    // FluidAudio's default trait adds NeMo text normalization, which would normalize the text a second time after
    // murmur's own rules. Turning it off also keeps its prebuilt Rust library out of murmurd.
    .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7", traits: [])
  ],
  targets: [
    // The client doesn't link FluidAudio, so it starts in milliseconds. It only sends requests to murmurd.
    .executableTarget(name: "murmur", dependencies: ["MurmurCore"]),
    .executableTarget(name: "murmurd", dependencies: ["MurmurCore", "ObjCTry", "FluidAudio"]),
    // The code that both executables share. The unit tests cover it.
    .target(name: "MurmurCore"),
    // Catches the Objective-C exceptions that AVAudioEngine raises, because Swift can't.
    .target(name: "ObjCTry"),
    .testTarget(name: "MurmurCoreTests", dependencies: ["MurmurCore", "ObjCTry"]),
  ],
  swiftLanguageModes: [.v6]
)
