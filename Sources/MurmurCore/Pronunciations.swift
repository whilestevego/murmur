import Foundation

/// Words Kokoro gets wrong, rewritten before speaking. Checked with `murmur phonemes`.
public enum Pronunciations {
  /// Acronyms that collide with dictionary words (ID → "id"), and tech words the model spells out or mangles.
  public static let defaults: [String: String] = [
    "ID": "I D", "IDs": "I Ds",
    "JSON": "Jason", "YAML": "yamel", "TOML": "tommel",
    "TODO": "to do", "TODOs": "to dos", "todo": "to do", "todos": "to dos", "Todo": "To do", "Todos": "To dos",
    "to-do": "to do", "to-dos": "to dos", "To-do": "To do", "TodoWrite": "to do write",
    "goto": "go to", "Goto": "Go to", "GOTO": "go to", "gotos": "go tos",
    "repos": "reepos", "Repos": "Reepos", "monorepo": "mono reepo", "Monorepo": "Mono reepo",
    "monorepos": "mono reepos", "Monorepos": "Mono reepos",
    "README": "read me", "npm": "N P M", "ssn": "S S N", "tv": "T V",
    // Exact sounds, between slashes: also the stem of rebased, rebasing…
    "rebase": "/ɹˈibˌAs/",
    "macOS": "mac O S", "GraphQL": "graph Q L", "OAuth": "oh auth",
    "kubectl": "cube control", "nginx": "engine X",
    "stdout": "standard out", "stderr": "standard error", "stdin": "standard in",
  ]

  /// Your own, one per line: `WORD = how to say it`. They win over the defaults.
  public static let file = Paths.home.appendingPathComponent(".config/murmur/pronunciations")

  /// `WORD = spoken` lines; blank lines and `#` comments are skipped.
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

  /// The defaults with your file on top. Read on every request, so an edit applies to the next thing said.
  public static func load() -> [String: String] {
    let mine = (try? String(contentsOf: file, encoding: .utf8)).map(parse) ?? [:]
    return defaults.merging(mine) { _, yours in yours }
  }
}

extension Pronunciations {
  /// Respellings (`JSON = Jason`) and exact sounds (`rebase = /ɹˈibˌAs/`, as `murmur phonemes` prints them).
  public static func split(_ all: [String: String]) -> (respell: [String: String], sounds: [String: String]) {
    let isSound = { (v: String) in v.count > 2 && v.hasPrefix("/") && v.hasSuffix("/") }
    return (
      all.filter { !isSound($0.value) },
      all.filter { isSound($0.value) }.mapValues { String($0.dropFirst().dropLast()) }
    )
  }
}

/// Text as murmur says it: tech text cleaned up, your respellings applied, cut into sentences, each with the exact
/// sounds FluidAudio should use for its words (yours, and the ones misaki's rules work out).
public func prepare(
  _ text: String, _ pronunciations: [String: String], _ lexicon: Lexicon
) -> [(text: String, sounds: [String: String])] {
  let (respell, mine) = Pronunciations.split(pronunciations)
  let clean = normalize(text) {
    lexicon.entry($0) != nil || respell[$0] != nil || mine[$0] != nil || mine[$0.lowercased()] != nil
  }
  return sentences(pronounce(clean, respell)).map { ($0, lexicon.sounds(for: $0, mine: mine)) }
}

/// Rewrites whole words only, matching case exactly: "ID" changes, "id" and "IDEA" don't.
public func pronounce(_ text: String, _ dictionary: [String: String]) -> String {
  guard !dictionary.isEmpty else { return text }
  let words = dictionary.keys.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:))
  let pattern = "(?<![\\p{L}\\p{N}_])(" + words.joined(separator: "|") + ")(?![\\p{L}\\p{N}_])"
  return replace(text, pattern) { dictionary[$0[0]] }
}
