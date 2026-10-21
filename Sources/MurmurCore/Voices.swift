import Foundation

/// A Kokoro voice.
public struct VoiceInfo: Equatable, Sendable {
  /// The voice's name, such as "af_nicole".
  ///
  /// The first letter gives the accent, and the second letter gives the gender.
  public let name: String
  /// The accent and gender, such as "American female".
  public let group: String
  /// The voice's overall grade from Kokoro, from A to F.
  ///
  /// The grade reflects the quality and amount of the voice's training audio.
  public let grade: String

  /// The voice's display name, such as "Nicole" for "af_nicole".
  public var label: String { String(name.dropFirst(3)).capitalized }
}

/// The 28 English voices of Kokoro v1.0.
///
/// The voices are grouped by accent and gender, which the first two letters of each name give. The grades come from
/// [Kokoro's list of voices](https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md).
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

/// The installed voice packs.
public enum VoicePacks {
  /// The size of a voice pack, in bytes.
  ///
  /// A pack holds Kokoro's style vectors, which are 510 by 256 32-bit floats.
  public static let bytes = 510 * 256 * 4

  /// The directory that FluidAudio reads voice packs from.
  ///
  /// It's in the installed bundle if there is one, and in FluidAudio's download cache otherwise.
  public static var directory: URL {
    Paths.bundleInstalled ? Paths.bundleANE : Paths.fluidCache.appendingPathComponent("kokoro-82m-coreml/ANE")
  }

  /// Returns whether a voice's pack is installed.
  ///
  /// - Parameter name: The name of the voice.
  /// - Returns: `true` if the pack is in ``directory``.
  public static func isInstalled(_ name: String) -> Bool {
    FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(name).bin").path)
  }

  /// Returns the download URL for a voice's pack.
  ///
  /// FluidAudio publishes only af_heart for the Neural Engine. This repository has the same raw packs for every voice,
  /// one file each.
  static func remote(_ name: String) -> URL? {
    URL(string: "https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/main/voices/\(name).bin")
  }

  /// An error from installing a voice pack.
  public enum InstallError: Error, CustomStringConvertible {
    /// A voice name that isn't in ``voiceCatalog``.
    case unknown(String)
    /// A download that failed, with the reason.
    case download(String)
    /// A download that wasn't the size of a voice pack, with its size in bytes.
    case badSize(Int)

    /// A message that describes the error.
    public var description: String {
      switch self {
      case .unknown(let name): return "unknown voice \(name) (see: murmur voices)"
      case .download(let why): return "download failed: \(why)"
      case .badSize(let n): return "download was \(n) bytes, expected \(VoicePacks.bytes)"
      }
    }
  }

  /// Downloads and installs a voice pack.
  ///
  /// A pack is about 510 KB. The download's size is checked before the pack is moved into place, and the move is
  /// atomic.
  ///
  /// - Parameter name: The name of the voice.
  /// - Throws: ``InstallError`` if the voice is unknown, or if the download fails or has the wrong size.
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
