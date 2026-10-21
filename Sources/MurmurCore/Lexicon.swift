import Foundation

/// Kokoro's word list (misaki's gold and silver dictionaries, as FluidAudio caches them), and misaki's rules for words
/// it lacks: a known word plus -s, -'s, -ed or -ing, and hyphenated compounds. FluidAudio sends every word missing from
/// the list to a small neural guesser, which misreads some (today's → "TOE-days"). murmur works those words out first
/// and hands FluidAudio their exact sounds.
public struct Lexicon: Sendable {
  /// Lower-cased word → sounds, and exact spelling → sounds (names, abbreviations, single letters).
  public let lower: [String: String]
  public let cased: [String: String]

  public init(lower: [String: String] = [:], cased: [String: String] = [:]) {
    self.lower = lower
    self.cased = cased
  }

  /// The list FluidAudio itself reads; empty when the model isn't installed, which only turns these rules off.
  public static func load() -> Lexicon {
    for dir in [Paths.models.appendingPathComponent("kokoro"), Paths.g2p] {
      guard let data = try? Data(contentsOf: dir.appendingPathComponent("us_lexicon_cache.json")),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: [String]]]
      else { continue }
      return Lexicon(
        lower: (json["lower"] ?? [:]).mapValues { $0.joined() },
        cased: (json["caseSensitive"] ?? [:]).mapValues { $0.joined() })
    }
    return Lexicon()
  }

  /// What FluidAudio's own lookup finds: the exact spelling, then the lower-cased one.
  public func entry(_ word: String) -> String? {
    let key = String(word.lowercased().unicodeScalars.filter { Self.keyScalars.contains($0) })
    return cased[word] ?? cased[key] ?? lower[key]
  }

  /// Exact sounds for the words in `text` that the list lacks but the rules can work out, plus your own (`mine`), which
  /// win and also count as known stems: with `rebase` set, `rebased` follows.
  public func sounds(for text: String, mine: [String: String] = [:]) -> [String: String] {
    var out: [String: String] = [:]
    for word in Self.words(text) where out[word] == nil {
      if let s = mine[word] ?? mine[word.lowercased()] {
        out[word] = s
      } else if Self.isInitialismPlural(word), let s = derive(word, mine) {
        out[word] = s  // APIs is "A P Is", not the bee genus apis
      } else if entry(word) == nil && !Self.isInitialism(word), let s = derive(word, mine) {
        out[word] = s
      }
    }
    return out
  }

  private static let keyScalars = CharacterSet.letters.union(.decimalDigits).union(CharacterSet(charactersIn: "'"))
  // swift-format-ignore: NeverUseForceTry
  // A constant pattern: if it didn't compile, every test would fail.
  private static let wordRegex = try! NSRegularExpression(
    pattern: "[\\p{L}\\p{N}][\\p{L}\\p{N}-]*(?:'[\\p{L}\\p{N}]+)*")

  /// Words as FluidAudio splits them: letters and digits, with inner apostrophes and hyphens.
  static func words(_ text: String) -> [String] {
    let source = text as NSString
    return wordRegex.matches(in: text, range: NSRange(location: 0, length: source.length)).map {
      source.substring(with: $0.range)
    }
  }

  /// `PRs`, `API's`: letters to spell, plus an ending.
  static func isInitialismPlural(_ word: String) -> Bool {
    word.range(of: "^[A-Z]{2,5}'?s$", options: .regularExpression) != nil
  }

  /// FluidAudio spells these as letters on its own (`FBI`).
  static func isInitialism(_ word: String) -> Bool {
    (2...5).contains(word.count) && word.allSatisfy { $0.isASCII && $0.isUppercase && $0.isLetter }
  }

  // MARK: - misaki's rules (misaki/en.py: Lexicon.lookup, stem_s, stem_ed, stem_ing)

  private func lookup(_ word: String, _ mine: [String: String]) -> String? {
    if let s = mine[word] ?? mine[word.lowercased()] { return s }
    if word.count > 1 && word == word.uppercased() && word.allSatisfy(\.isLetter) {
      return cased[word] ?? spell(word)
    }
    return entry(word)
  }

  /// `PR` → "pˈi ˈɑɹ", from the single-letter entries.
  private func spell(_ word: String) -> String? {
    let letters = word.compactMap { cased[String($0)] }
    return letters.count == word.count ? letters.joined(separator: " ") : nil
  }

  private func derive(_ word: String, _ mine: [String: String]) -> String? {
    if word.contains("-") {
      let pieces = word.split(separator: "-")
      let parts = pieces.compactMap { lookup(String($0), mine) ?? derive(String($0), mine) }
      return pieces.count > 1 && parts.count == pieces.count ? parts.joined(separator: " ") : nil
    }
    for w in [word, word.lowercased()] {
      if let s = stemS(w, mine) ?? stemEd(w, mine) ?? stemIng(w, mine) { return s }
    }
    return nil
  }

  private func stemS(_ word: String, _ mine: [String: String]) -> String? {
    guard word.count >= 3, word.hasSuffix("s") else { return nil }
    let stem: String
    if !word.hasSuffix("ss"), lookup(String(word.dropLast()), mine) != nil {
      stem = String(word.dropLast())
    } else if word.hasSuffix("'s") || (word.count > 4 && word.hasSuffix("es") && !word.hasSuffix("ies")),
      lookup(String(word.dropLast(2)), mine) != nil
    {
      stem = String(word.dropLast(2))
    } else if word.count > 4 && word.hasSuffix("ies"), lookup(word.dropLast(3) + "y", mine) != nil {
      stem = word.dropLast(3) + "y"
    } else {
      return nil
    }
    return lookup(stem, mine).flatMap(Self.addS)
  }

  private func stemEd(_ word: String, _ mine: [String: String]) -> String? {
    guard word.count >= 4, word.hasSuffix("d") else { return nil }
    let stem: String
    if !word.hasSuffix("dd"), lookup(String(word.dropLast()), mine) != nil {
      stem = String(word.dropLast())
    } else if word.count > 4 && word.hasSuffix("ed") && !word.hasSuffix("eed"),
      lookup(String(word.dropLast(2)), mine) != nil
    {
      stem = String(word.dropLast(2))
    } else if word.range(of: "([bdgklmnprtvz])\\1ed$", options: .regularExpression) != nil,
      lookup(String(word.dropLast(3)), mine) != nil
    {
      stem = String(word.dropLast(3))  // stopped: like stem_ing's stopping, which misaki's stem_ed lacks
    } else {
      return nil
    }
    return lookup(stem, mine).flatMap(Self.addEd)
  }

  private func stemIng(_ word: String, _ mine: [String: String]) -> String? {
    guard word.count >= 5, word.hasSuffix("ing") else { return nil }
    let base = String(word.dropLast(3))
    let stem: String
    if word.count > 5, lookup(base, mine) != nil {
      stem = base
    } else if lookup(base + "e", mine) != nil {
      stem = base + "e"
    } else if word.count > 5, word.range(of: "([bcdgklmnprstvxz])\\1ing$|cking$", options: .regularExpression) != nil,
      lookup(String(word.dropLast(4)), mine) != nil
    {
      stem = String(word.dropLast(4))
    } else {
      return nil
    }
    return lookup(stem, mine).flatMap(Self.addIng)
  }

  /// Vowels after which an American t flaps (water → "waɾer").
  private static let taus: Set<Character> = Set("AIOWYiuæɑəɛɪɹʊʌ")

  static func addS(_ stem: String) -> String? {
    guard let last = stem.last else { return nil }
    if "ptkfθ".contains(last) { return stem + "s" }
    if "szʃʒʧʤ".contains(last) { return stem + "ᵻz" }
    return stem + "z"
  }

  static func addEd(_ stem: String) -> String? {
    guard let last = stem.last else { return nil }
    if "pkfθʃsʧ".contains(last) { return stem + "t" }
    if last == "d" { return stem + "ᵻd" }
    if last != "t" { return stem + "d" }
    if stem.count < 2 { return stem + "ɪd" }
    if taus.contains(stem[stem.index(stem.endIndex, offsetBy: -2)]) { return stem.dropLast() + "ɾᵻd" }
    return stem + "ᵻd"
  }

  static func addIng(_ stem: String) -> String? {
    guard let last = stem.last else { return nil }
    if stem.count > 1 && last == "t" && taus.contains(stem[stem.index(stem.endIndex, offsetBy: -2)]) {
      return stem.dropLast() + "ɾɪŋ"
    }
    return stem + "ɪŋ"
  }
}
