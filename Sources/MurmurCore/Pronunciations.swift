import Foundation

/// Respellings and exact pronunciations for words that Kokoro says wrong.
///
/// Each default was checked with `murmur phonemes`.
public enum Pronunciations {
  /// The built-in pronunciations.
  ///
  /// They cover acronyms that match dictionary words, such as "ID", which Kokoro reads as "id", and technical words
  /// that Kokoro spells out or mispronounces.
  public static let defaults: [String: String] = [
    "ID": "I D", "IDs": "I Ds",
    "JSON": "Jason", "YAML": "yamel", "TOML": "tommel",
    "TODO": "to do", "TODOs": "to dos", "todo": "to do", "todos": "to dos", "Todo": "To do", "Todos": "To dos",
    "to-do": "to do", "to-dos": "to dos", "To-do": "To do", "TodoWrite": "to do write",
    "goto": "go to", "Goto": "Go to", "GOTO": "go to", "gotos": "go tos",
    "repos": "reepos", "Repos": "Reepos", "monorepo": "mono reepo", "Monorepo": "Mono reepo",
    "monorepos": "mono reepos", "Monorepos": "Mono reepos",
    "README": "read me", "npm": "N P M", "ssn": "S S N", "tv": "T V",
    // Phonemes between slashes are used as they are, and also as the stem of words such as "rebased".
    "rebase": "/ɹˈibˌAs/", "debounce": "/dibˈWns/", "plugin": "/plˈʌɡˌɪn/",
    "macOS": "mac O S", "GraphQL": "graph Q L", "OAuth": "oh auth",
    "kubectl": "cube control", "nginx": "engine X",
    "stdout": "standard out", "stderr": "standard error", "stdin": "standard in",
  ]

  /// The file of custom pronunciations.
  ///
  /// Each line has the form `WORD = spoken form`. Custom pronunciations take precedence over the defaults. The
  /// `--pronunciations` option chooses a different file.
  public static let file = Paths.home.appendingPathComponent(".config/murmur/pronunciations")

  /// Parses the contents of a pronunciation file.
  ///
  /// Blank lines, lines without an equals sign, and lines that start with `#` are skipped.
  ///
  /// - Parameter text: The contents of the file.
  /// - Returns: The spoken form of each word.
  public static func parse(_ text: String) -> [String: String] {
    var out: [String: String] = [:]
    for line in text.split(whereSeparator: \.isNewline) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard !trimmed.hasPrefix("#"), let eq = trimmed.firstIndex(of: "=") else { continue }
      let word = trimmed[..<eq].trimmingCharacters(in: .whitespaces)
      let spoken = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
      if !word.isEmpty && !spoken.isEmpty { out[word] = spoken }
    }
    return out
  }

  /// Returns the default pronunciations, overridden by the custom ones in a file.
  ///
  /// The file is read on every call, so an edit applies to the next request. A missing file adds no custom
  /// pronunciations.
  ///
  /// - Parameter file: The file of custom pronunciations.
  /// - Returns: The spoken form of each word.
  public static func load(from file: URL) -> [String: String] {
    let mine = (try? String(contentsOf: file, encoding: .utf8)).map(parse) ?? [:]
    return defaults.merging(mine) { _, yours in yours }
  }
}

extension Pronunciations {
  /// Separates respellings from exact pronunciations.
  ///
  /// A respelling replaces a word with other text, such as `JSON = Jason`. An exact pronunciation gives phonemes
  /// between slashes, in the form `murmur phonemes` prints, such as `rebase = /ɹˈibˌAs/`.
  ///
  /// - Parameter all: The pronunciations to separate.
  /// - Returns: The respellings, and the exact pronunciations with their slashes removed.
  public static func split(_ all: [String: String]) -> (respell: [String: String], sounds: [String: String]) {
    let isSound = { (v: String) in v.count > 2 && v.hasPrefix("/") && v.hasSuffix("/") }
    return (
      all.filter { !isSound($0.value) },
      all.filter { isSound($0.value) }.mapValues { String($0.dropFirst().dropLast()) }
    )
  }
}

/// Prepares text for speaking.
///
/// The text is normalized, respelled and split into sentences. Each sentence comes with the phonemes FluidAudio should
/// use for its words, from the exact pronunciations and from misaki's rules.
///
/// - Parameters:
///   - text: The text to speak.
///   - pronunciations: The respellings and exact pronunciations to apply.
///   - lexicon: The dictionary that misaki's rules build on.
/// - Returns: The sentences, each with the phonemes for its words.
public func prepare(
  _ text: String, _ pronunciations: [String: String], _ lexicon: Lexicon
) -> [(text: String, sounds: [String: String])] {
  let (respell, mine) = Pronunciations.split(pronunciations)
  let clean = normalize(text) {
    lexicon.entry($0) != nil || respell[$0] != nil || mine[$0] != nil || mine[$0.lowercased()] != nil
  }
  return sentences(pronounce(clean, respell)).map { ($0, lexicon.sounds(for: $0, mine: mine)) }
}

/// Replaces words with their respellings.
///
/// Only whole words that match exactly, including case, are replaced. For example, with a respelling for "ID", the
/// words "id" and "IDEA" are left alone.
///
/// - Parameters:
///   - text: The text to respell.
///   - dictionary: The respelling for each word.
/// - Returns: The respelled text.
public func pronounce(_ text: String, _ dictionary: [String: String]) -> String {
  guard !dictionary.isEmpty else { return text }
  let words = dictionary.keys.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:))
  let pattern = "(?<![\\p{L}\\p{N}_])(" + words.joined(separator: "|") + ")(?![\\p{L}\\p{N}_])"
  return replace(text, pattern) { dictionary[$0[0]] }
}
