import Foundation

/// A request from `murmur` to `murmurd`.
///
/// Each connection carries one request, encoded as JSON.
public enum Request: Codable, Equatable, Sendable {
  /// A request to speak text.
  case speak(Speech)
  /// A request to stop speaking and discard any queued speech.
  case stop
}

/// Text to speak, with the voice and speed to speak it in.
public struct Speech: Codable, Equatable, Sendable {
  /// The text to speak.
  ///
  /// It can hold several sentences, and text such as paths and numbers that is normalized before it's spoken.
  public var text: String
  /// The name of the voice, which must be in ``voiceCatalog``.
  public var voice: String
  /// The speaking rate, where 1 is normal speed and larger values are faster.
  ///
  /// It must be finite and greater than 0.
  public var speed: Float
  /// A Boolean value that indicates whether to stop current and queued speech before speaking.
  public var interrupt: Bool

  /// Creates a speech request.
  ///
  /// - Parameters:
  ///   - text: The text to speak.
  ///   - voice: The name of the voice, which must be in ``voiceCatalog``.
  ///   - speed: The speaking rate, where 1 is normal speed.
  ///   - interrupt: Whether to stop current and queued speech first.
  public init(text: String = "", voice: String = Defaults.voice, speed: Float = 1, interrupt: Bool = false) {
    self.text = text
    self.voice = voice
    self.speed = speed
    self.interrupt = interrupt
  }

  /// Creates a speech request from command-line arguments.
  ///
  /// The options are `-v` or `--voice`, `-s` or `--speed`, and `-i` or `--interrupt`. The remaining arguments are
  /// joined with spaces to form the text. If there are none, ``text`` is empty.
  ///
  /// - Parameter arguments: The arguments, without the program name.
  /// - Throws: ``UsageError`` if an option is missing its value, names an unknown voice, or gives a speed that isn't a
  ///   finite number greater than 0.
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
      // Everything after "--" is text, even an argument that looks like an option.
      case "--":
        words += args
        args = []
      default: words.append(arg)
      }
    }
    text = words.joined(separator: " ")
  }
}

/// An error in command-line arguments.
public struct UsageError: Error, CustomStringConvertible, Equatable {
  /// A message that describes the error, such as "--voice needs a name".
  public let description: String
  /// Creates an error with a message.
  ///
  /// - Parameter description: A message that describes the error.
  public init(_ description: String) { self.description = description }
}

/// Fixed settings that murmur doesn't offer as options.
public enum Defaults {
  /// The name of the voice to use when none is given.
  ///
  /// It's the voice Kokoro grades highest, and the only one FluidAudio publishes for the Neural Engine.
  public static let voice = "af_heart"
  /// The sample rate of Kokoro's mono output, in hertz.
  public static let sampleRate = 24_000.0
  /// The time, in seconds, that murmurd waits with nothing to speak before it exits.
  public static let idleExit: TimeInterval = 10 * 60
  /// The maximum total size of the phrase cache, in bytes.
  public static let cacheBytes = 32 * 1024 * 1024
}

/// The locations of murmur's files.
public enum Paths {
  /// The current user's home directory.
  public static let home = FileManager.default.homeDirectoryForCurrentUser
  /// The directory for files that murmur can re-create, such as the socket, the log and the phrase cache.
  public static let caches = home.appendingPathComponent("Library/Caches/murmur")
  /// The Unix domain socket that murmurd listens on.
  ///
  /// The path is kept short because a Unix socket path must fit in 104 bytes.
  public static let socket = caches.appendingPathComponent("murmurd.sock")
  /// The directory that holds the phrase cache.
  public static let phrases = caches.appendingPathComponent("phrases")
  /// The file that murmurd writes its log to.
  public static let log = caches.appendingPathComponent("murmurd.log")
  /// The directory of the installed Kokoro Core ML bundle.
  ///
  /// The bundle holds the seven compiled model stages, the vocabulary and the voice packs.
  public static let models = home.appendingPathComponent("Library/Application Support/murmur/KokoroBundle")
  /// The directory in the bundle that holds the Neural Engine models, the vocabulary and the voice packs.
  public static let bundleANE = models.appendingPathComponent("kokoro-82m-coreml/ANE")
  /// A Boolean value that indicates whether a Kokoro bundle is installed in ``models``.
  ///
  /// Without a bundle, FluidAudio downloads the model into ``fluidCache``.
  public static var bundleInstalled: Bool {
    FileManager.default.fileExists(atPath: bundleANE.appendingPathComponent("vocab.json").path)
  }
  /// The directory where FluidAudio caches the models it downloads.
  public static let fluidCache = home.appendingPathComponent(".cache/fluidaudio/Models")
  /// The directory that FluidAudio reads its English grapheme-to-phoneme assets from.
  ///
  /// FluidAudio uses this fixed path on macOS.
  public static let g2p = fluidCache.appendingPathComponent("kokoro")
}

/// Splits text into sentences.
///
/// A sentence ends at a line break, or at a period, exclamation mark or question mark followed by a space. A period
/// after an abbreviation such as "e.g." or "Dr." doesn't end a sentence. Speaking sentence by sentence lets the first
/// one play while the rest are still rendering.
///
/// - Parameter text: The text to split.
/// - Returns: The sentences, with surrounding spaces trimmed and empty ones removed.
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

/// Returns whether the last word of the text is an abbreviation whose period doesn't end a sentence.
private func endsInAbbreviation(_ text: String) -> Bool {
  let word = text.split(separator: " ").last.map { $0.trimmingCharacters(in: .punctuationCharacters).lowercased() }
  return word.map(["e.g", "i.e", "vs", "dr", "mr", "mrs", "ms"].contains) ?? false
}

/// Returns a string that identifies a set of pronunciations.
///
/// Adding it to a sentence's cache key means that changing a pronunciation renders the sentence again.
///
/// - Parameter sounds: The pronunciations, as phonemes by word.
/// - Returns: The pronunciations sorted by word, so that equal sets give equal strings.
public func soundsKey(_ sounds: [String: String]) -> String {
  sounds.sorted { $0.key < $1.key }.map { "|\($0.key)=\($0.value)" }.joined()
}

/// Returns the cache key for a rendered sentence.
///
/// The key is the 64-bit FNV-1a hash of the voice, speed and text. Unlike `hashValue`, it's the same in every process.
///
/// - Parameters:
///   - text: The sentence.
///   - voice: The name of the voice.
///   - speed: The speaking rate.
/// - Returns: The hash, in hexadecimal.
public func cacheKey(_ text: String, voice: String, speed: Float) -> String {
  var hash: UInt64 = 0xcbf2_9ce4_8422_2325
  for byte in "\(voice)|\(speed)|\(text)".utf8 {
    hash ^= UInt64(byte)
    hash = hash &* 0x100_0000_01b3
  }
  return String(hash, radix: 16)
}
