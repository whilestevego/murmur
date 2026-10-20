import Foundation

/// One request from `murmur` to `murmurd`: a single JSON line per connection.
public struct Request: Codable, Equatable {
  public var text: String
  public var voice: String
  public var speed: Float
  /// Cut off whatever is playing (and anything queued) before speaking.
  public var interrupt: Bool
  /// Only stop: no text is spoken.
  public var stop: Bool

  public init(text: String = "", voice: String = Defaults.voice, speed: Float = 1, interrupt: Bool = false, stop: Bool = false) {
    self.text = text
    self.voice = voice
    self.speed = speed
    self.interrupt = interrupt
    self.stop = stop
  }
}

public enum Defaults {
  public static let voice = "af_heart"
  /// Kokoro renders 24 kHz mono.
  public static let sampleRate = 24_000.0
  /// murmurd exits after this long with nothing to say; the next `murmur` starts it again.
  public static let idleExit: TimeInterval = 10 * 60
  /// Phrase cache cap, evicting the least recently played first.
  public static let cacheBytes = 32 * 1024 * 1024
}

public enum Paths {
  public static let home = FileManager.default.homeDirectoryForCurrentUser
  public static let caches = home.appendingPathComponent("Library/Caches/murmur")
  /// Short on purpose: a unix socket path must fit in 104 bytes.
  public static let socket = caches.appendingPathComponent("murmurd.sock")
  public static let phrases = caches.appendingPathComponent("phrases")
  public static let log = caches.appendingPathComponent("murmurd.log")
  /// The Kokoro CoreML bundle (the 7 .mlmodelc stages, vocab and voice packs).
  public static let models = home.appendingPathComponent("Library/Application Support/murmur/KokoroBundle")
  /// The bundle's Neural Engine models, vocab and voice packs.
  public static let bundleANE = models.appendingPathComponent("kokoro-82m-coreml/ANE")
  /// Whether `murmur setup --from` installed a bundle; without one, FluidAudio downloads into `fluidCache`.
  public static var bundleInstalled: Bool {
    FileManager.default.fileExists(atPath: bundleANE.appendingPathComponent("vocab.json").path)
  }
  /// FluidAudio's own download cache.
  public static let fluidCache = home.appendingPathComponent(".cache/fluidaudio/Models")
  /// FluidAudio reads its English pronunciation (G2P) assets from this fixed path on macOS.
  public static let g2p = fluidCache.appendingPathComponent("kokoro")
}

/// Splits text into sentences so the first one plays while the rest are still being rendered.
public func sentences(_ text: String) -> [String] {
  var out: [String] = []
  var current = ""
  let chars = Array(text)
  for (i, c) in chars.enumerated() {
    if c == "\n" {
      out.append(current)
      current = ""
      continue
    }
    current.append(c)
    let next = i + 1 < chars.count ? chars[i + 1] : " "
    if ".!?".contains(c) && (next == " " || next == "\n") {
      out.append(current)
      current = ""
    }
  }
  out.append(current)
  return out.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
}

/// A stable cache key (FNV-1a 64) for one rendered sentence: same text, voice and speed, same audio.
/// The exact sounds a sentence was rendered with, as part of its cache key: a new pronunciation re-renders it.
public func soundsKey(_ sounds: [String: String]) -> String {
  sounds.sorted { $0.key < $1.key }.map { "|\($0.key)=\($0.value)" }.joined()
}

public func cacheKey(_ text: String, voice: String, speed: Float) -> String {
  var hash: UInt64 = 0xcbf2_9ce4_8422_2325
  for byte in "\(voice)|\(speed)|\(text)".utf8 {
    hash ^= UInt64(byte)
    hash = hash &* 0x100_0000_01b3
  }
  return String(hash, radix: 16)
}
