import Foundation

/// Words Kokoro gets wrong, rewritten before speaking. Checked with `murmur phonemes`.
public enum Pronunciations {
  /// Acronyms that collide with dictionary words (ID → "id"), and tech words the model spells out or mangles.
  public static let defaults: [String: String] = [
    "ID": "I D", "IDs": "I Ds",
    "JSON": "Jason", "YAML": "yamel", "TOML": "tommel",
    "TODO": "to do", "TODOs": "to dos", "todo": "to do", "todos": "to dos", "Todo": "To do", "Todos": "To dos",
    "to-do": "to do", "to-dos": "to dos", "To-do": "To do", "TodoWrite": "to do write",
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

/// Rewrites whole words only, matching case exactly: "ID" changes, "id" and "IDEA" don't.
public func pronounce(_ text: String, _ dictionary: [String: String]) -> String {
  guard !dictionary.isEmpty else { return text }
  let words = dictionary.keys.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:))
  let pattern = "(?<![\\p{L}\\p{N}_])(" + words.joined(separator: "|") + ")(?![\\p{L}\\p{N}_])"
  guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
  let source = text as NSString
  var out = ""
  var last = 0
  for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
    out += source.substring(with: NSRange(location: last, length: match.range.location - last))
    out += dictionary[source.substring(with: match.range)] ?? source.substring(with: match.range)
    last = match.range.location + match.range.length
  }
  return out + source.substring(from: last)
}
