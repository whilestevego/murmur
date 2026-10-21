import Foundation

public struct VoiceInfo: Equatable, Sendable {
  public let name: String
  public let group: String
  /// Kokoro's own "Overall Grade" for the voice (A to F): how good and how plentiful its training audio was.
  public let grade: String

  /// The name to show: "af_nicole" → "Nicole".
  public var label: String { String(name.dropFirst(3)).capitalized }
}

/// Kokoro v1.0's 28 English voices, grouped by accent and gender (the name's first two letters), with the grades
/// from Kokoro's VOICES.md (https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md).
public let voiceCatalog: [VoiceInfo] = {
  let groups: [(String, String, KeyValuePairs<String, String>)] = [
    (
      "af", "American female",
      [
        "alloy": "C", "aoede": "C+", "bella": "A-", "heart": "A", "jessica": "D", "kore": "C+",
        "nicole": "B-", "nova": "C", "river": "D", "sarah": "C+", "sky": "C-",
      ]
    ),
    (
      "am", "American male",
      [
        "adam": "F+", "echo": "D", "eric": "D", "fenrir": "C+", "liam": "D", "michael": "C+",
        "onyx": "D", "puck": "C+", "santa": "D-",
      ]
    ),
    ("bf", "British female", ["alice": "D", "emma": "B-", "isabella": "C", "lily": "D"]),
    ("bm", "British male", ["daniel": "D", "fable": "C", "george": "C", "lewis": "D+"]),
  ]
  return groups.flatMap { prefix, group, voices in
    voices.map { VoiceInfo(name: "\(prefix)_\($0.key)", group: group, grade: $0.value) }
  }
}()

public enum VoicePacks {
  /// One voice pack: Kokoro's style vectors, 510 × 256 Float32.
  public static let bytes = 510 * 256 * 4

  /// Where the engine reads packs: the installed bundle, else FluidAudio's own download cache.
  public static var directory: URL {
    Paths.bundleInstalled ? Paths.bundleANE : Paths.fluidCache.appendingPathComponent("kokoro-82m-coreml/ANE")
  }

  public static func isInstalled(_ name: String) -> Bool {
    FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(name).bin").path)
  }

  /// FluidAudio only publishes af_heart for the Neural Engine; these are the same raw packs, one file per voice.
  static func remote(_ name: String) -> URL? {
    URL(string: "https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/main/voices/\(name).bin")
  }

  public enum InstallError: Error, CustomStringConvertible {
    case unknown(String)
    case download(String)
    case badSize(Int)
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
    guard voiceCatalog.contains(where: { $0.name == name }), let url = remote(name) else {
      throw InstallError.unknown(name)
    }
    var request = URLRequest(url: url)
    request.timeoutInterval = 30
    let data: Data
    do {
      let (body, response) = try await URLSession.shared.data(for: request)
      if let http = response as? HTTPURLResponse, http.statusCode != 200 {
        throw InstallError.download("HTTP \(http.statusCode)")
      }
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
