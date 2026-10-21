import Foundation

/// One request from `murmur` to `murmurd`: a single JSON line per connection.
public enum Request: Codable, Equatable, Sendable {
  case speak(Speech)
  /// Stop speaking and drop anything queued.
  case stop
}

/// Text to speak, and how.
public struct Speech: Codable, Equatable, Sendable {
  /// Raw text: murmurd cleans it up and splits it into sentences.
  public var text: String
  /// A name from `voiceCatalog`; murmurd installs it on first use.
  public var voice: String
  /// Kokoro's speaking rate: 1 is normal, above 1 faster.
  public var speed: Float
  /// Cut off whatever is playing (and anything queued) before speaking.
  public var interrupt: Bool

  /// Speech in the default voice at normal speed, queued after whatever is playing.
  public init(text: String = "", voice: String = Defaults.voice, speed: Float = 1, interrupt: Bool = false) {
    self.text = text
    self.voice = voice
    self.speed = speed
    self.interrupt = interrupt
  }

  /// Reads the options and words `murmur` was given.
  ///
  /// Empty text means no words were given, and murmur then reads stdin.
  public init(arguments: [String]) throws(UsageError) {
    self.init()
    var args = arguments
    var words: [String] = []
    while !args.isEmpty {
      let arg = args.removeFirst()
      switch arg {
      case "-v", "--voice":
        guard !args.isEmpty else { throw UsageError("--voice needs a name") }
        voice = args.removeFirst()
        guard voiceCatalog.contains(where: { $0.name == voice }) else {
          throw UsageError("unknown voice \(voice) (see: murmur voices)")
        }
      case "-s", "--speed":
        guard let s = args.isEmpty ? nil : Float(args.removeFirst()), s.isFinite, s > 0 else {
          throw UsageError("--speed needs a number")
        }
        speed = s
      case "-i", "--interrupt": interrupt = true
      case "--":  // everything after is text, even if it looks like a flag
        words += args
        args = []
      default: words.append(arg)
      }
    }
    text = words.joined(separator: " ")
  }
}

/// A mistake in the arguments `murmur` was given; it prints the message and exits with 1.
public struct UsageError: Error, CustomStringConvertible, Equatable {
  /// What was wrong, as `murmur` prints it after "murmur:".
  public let description: String
  /// An error with this message.
  public init(_ description: String) { self.description = description }
}

/// Settings murmur doesn't let you change.
public enum Defaults {
  /// The voice when `--voice` isn't given: the one Kokoro grades best, and the one FluidAudio ships.
  public static let voice = "af_heart"
  /// Kokoro renders 24 kHz mono.
  public static let sampleRate = 24_000.0
  /// murmurd exits after this long with nothing to say; the next `murmur` starts it again.
  public static let idleExit: TimeInterval = 10 * 60
  /// Phrase cache cap, evicting the least recently played first.
  public static let cacheBytes = 32 * 1024 * 1024
}

/// Where murmur keeps its files.
public enum Paths {
  /// The user's home folder.
  public static let home = FileManager.default.homeDirectoryForCurrentUser
  /// The socket, lock, log and phrase cache: everything murmur can rebuild if it's deleted.
  public static let caches = home.appendingPathComponent("Library/Caches/murmur")
  /// Short on purpose: a unix socket path must fit in 104 bytes.
  public static let socket = caches.appendingPathComponent("murmurd.sock")
  /// The phrase cache's rendered sentences.
  public static let phrases = caches.appendingPathComponent("phrases")
  /// murmurd's output; murmur starts it afresh once it passes 1 MB.
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
    if ".!?".contains(c) && (next == " " || next == "\n") && !(c == "." && endsInAbbreviation(current)) {
      out.append(current)
      current = ""
    }
  }
  out.append(current)
  return out.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
}

/// "Use e.g." or "Ask Dr.": a period that doesn't end the sentence.
private func endsInAbbreviation(_ text: String) -> Bool {
  let word = text.split(separator: " ").last.map { $0.trimmingCharacters(in: .punctuationCharacters).lowercased() }
  return word.map(["e.g", "i.e", "vs", "dr", "mr", "mrs", "ms"].contains) ?? false
}

/// The exact sounds a sentence was rendered with, as part of its cache key: a new pronunciation re-renders it.
public func soundsKey(_ sounds: [String: String]) -> String {
  sounds.sorted { $0.key < $1.key }.map { "|\($0.key)=\($0.value)" }.joined()
}

/// A stable cache key (FNV-1a 64) for one rendered sentence: same text, voice and speed, same audio.
public func cacheKey(_ text: String, voice: String, speed: Float) -> String {
  var hash: UInt64 = 0xcbf2_9ce4_8422_2325
  for byte in "\(voice)|\(speed)|\(text)".utf8 {
    hash ^= UInt64(byte)
    hash = hash &* 0x100_0000_01b3
  }
  return String(hash, radix: 16)
}
