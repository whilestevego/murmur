import Foundation

public struct VoiceInfo: Equatable {
  public let name: String
  public let group: String

  /// "af_nicole" → "Nicole"
  public var label: String { String(name.dropFirst(3)).capitalized }
}

/// Kokoro v1.0's 28 English voices, grouped by accent and gender (the name's first two letters).
public let voiceCatalog: [VoiceInfo] = {
  let groups = [
    ("af", "American female", ["alloy", "aoede", "bella", "heart", "jessica", "kore", "nicole", "nova", "river", "sarah", "sky"]),
    ("am", "American male", ["adam", "echo", "eric", "fenrir", "liam", "michael", "onyx", "puck", "santa"]),
    ("bf", "British female", ["alice", "emma", "isabella", "lily"]),
    ("bm", "British male", ["daniel", "fable", "george", "lewis"]),
  ]
  return groups.flatMap { prefix, group, names in names.map { VoiceInfo(name: "\(prefix)_\($0)", group: group) } }
}()

public enum VoicePacks {
  /// One voice pack: Kokoro's style vectors, 510 × 256 Float32.
  public static let bytes = 510 * 256 * 4

  /// Where the engine reads packs: the installed bundle, else FluidAudio's own download cache.
  public static var directory: URL {
    let bundled = Paths.models.appendingPathComponent("kokoro-82m-coreml/ANE")
    return FileManager.default.fileExists(atPath: bundled.appendingPathComponent("vocab.json").path)
      ? bundled
      : Paths.home.appendingPathComponent(".cache/fluidaudio/Models/kokoro-82m-coreml/ANE")
  }

  public static func isInstalled(_ name: String) -> Bool {
    FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(name).bin").path)
  }

  /// FluidAudio only publishes af_heart for the Neural Engine; these are the same raw packs, one file per voice.
  static func remote(_ name: String) -> URL {
    URL(string: "https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/main/voices/\(name).bin")!
  }

  public enum InstallError: Error, CustomStringConvertible {
    case unknown(String), download(String), badSize(Int)
    public var description: String {
      switch self {
      case .unknown(let name): return "unknown voice \(name) (see: murmur voices)"
      case .download(let why): return "download failed: \(why)"
      case .badSize(let n): return "download was \(n) bytes, expected \(VoicePacks.bytes)"
      }
    }
  }

  /// Downloads one pack (~510 KB), checks its size, and moves it into place atomically.
  public static func install(_ name: String) async throws {
    guard voiceCatalog.contains(where: { $0.name == name }) else { throw InstallError.unknown(name) }
    var request = URLRequest(url: remote(name))
    request.timeoutInterval = 30
    let data: Data
    do {
      let (body, response) = try await URLSession.shared.data(for: request)
      if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw InstallError.download("HTTP \(http.statusCode)") }
      data = body
    } catch let error as InstallError {
      throw error
    } catch {
      throw InstallError.download(error.localizedDescription)
    }
    guard data.count == bytes else { throw InstallError.badSize(data.count) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try data.write(to: directory.appendingPathComponent("\(name).bin"), options: .atomic)
  }
}
