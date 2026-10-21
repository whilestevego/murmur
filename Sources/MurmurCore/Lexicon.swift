import Foundation

/// Kokoro's pronunciation dictionary, with misaki's rules for words it doesn't list.
///
/// The dictionary is misaki's gold and silver lists, as FluidAudio caches them. FluidAudio sends every word that isn't
/// listed to a small neural model, which misreads some of them. For example, it reads "today's" as "TOE-days". The
/// rules work out the pronunciation of a listed word with -s, -'s, -ed or -ing added, and of a hyphenated compound of
/// listed words, so that FluidAudio can be given the exact phonemes instead.
public struct Lexicon: Sendable {
  /// The phonemes for each word, keyed by its lowercase spelling.
  public let lower: [String: String]
  /// The phonemes for words whose case matters, such as names, abbreviations and single letters, keyed by exact spelling.
  public let cased: [String: String]

  /// Creates a lexicon from word lists.
  ///
  /// - Parameters:
  ///   - lower: The phonemes for each word, keyed by its lowercase spelling.
  ///   - cased: The phonemes for words whose case matters, keyed by exact spelling.
  public init(lower: [String: String] = [:], cased: [String: String] = [:]) {
    self.lower = lower
    self.cased = cased
  }

  /// Loads the dictionary that FluidAudio reads.
  ///
  /// - Returns: The dictionary, or an empty lexicon if the model isn't installed. With an empty lexicon, the rules don't
  ///   change any pronunciations.
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

  /// Returns the phonemes for a word, looked up the same way FluidAudio does.
  ///
  /// The exact spelling is tried first, then the lowercase spelling.
  ///
  /// - Parameter word: The word to look up.
  /// - Returns: The phonemes, or `nil` if the dictionary doesn't list the word.
  public func entry(_ word: String) -> String? {
    let key = String(word.lowercased().unicodeScalars.filter { Self.keyScalars.contains($0) })
    return cased[word] ?? cased[key] ?? lower[key]
  }

  /// Returns the phonemes for the words in a text that the rules can work out.
  ///
  /// Words the dictionary lists are left out, because FluidAudio already reads them correctly. Custom pronunciations
  /// take precedence over the dictionary, and also serve as stems. For example, a custom pronunciation of "rebase" also
  /// gives the pronunciation of "rebased".
  ///
  /// - Parameters:
  ///   - text: The text to find words in.
  ///   - mine: Custom pronunciations, as phonemes by word.
  /// - Returns: The phonemes by word, for each word the rules or the custom pronunciations cover.
  public func sounds(for text: String, mine: [String: String] = [:]) -> [String: String] {
    var out: [String: String] = [:]
    for word in Self.words(text) where out[word] == nil {
      if let s = mine[word] ?? mine[word.lowercased()] {
        out[word] = s
      } else if Self.isInitialismPlural(word), let s = derive(word, mine) {
        // Spell out "APIs" as letters, because the dictionary lists the bee genus "apis".
        out[word] = s
      } else if entry(word) == nil && !Self.isInitialism(word), let s = derive(word, mine) {
        out[word] = s
      }
    }
    return out
  }

  private static let keyScalars = CharacterSet.letters.union(.decimalDigits).union(CharacterSet(charactersIn: "'"))
  // swift-format-ignore: NeverUseForceTry
  // The pattern is a constant, so a mistake in it fails every test.
  private static let wordRegex = try! NSRegularExpression(
    pattern: "[\\p{L}\\p{N}][\\p{L}\\p{N}-]*(?:'[\\p{L}\\p{N}]+)*")

  /// Splits text into words the same way FluidAudio does.
  ///
  /// A word is a run of letters and digits, which can contain apostrophes and hyphens.
  static func words(_ text: String) -> [String] {
    let source = text as NSString
    return wordRegex.matches(in: text, range: NSRange(location: 0, length: source.length)).map {
      source.substring(with: $0.range)
    }
  }

  /// Returns whether a word is an initialism with a plural or possessive ending, such as "PRs" or "API's".
  static func isInitialismPlural(_ word: String) -> Bool {
    word.range(of: "^[A-Z]{2,5}'?s$", options: .regularExpression) != nil
  }

  /// Returns whether a word is an initialism, such as "FBI", which FluidAudio spells out by itself.
  static func isInitialism(_ word: String) -> Bool {
    (2...5).contains(word.count) && word.allSatisfy { $0.isASCII && $0.isUppercase && $0.isLetter }
  }

  // MARK: - misaki's rules

  // These follow `Lexicon.lookup`, `stem_s`, `stem_ed` and `stem_ing` in misaki's `en.py`.

  private func lookup(_ word: String, _ mine: [String: String]) -> String? {
    if let s = mine[word] ?? mine[word.lowercased()] { return s }
    if word.count > 1 && word == word.uppercased() && word.allSatisfy(\.isLetter) {
      return cased[word] ?? spell(word)
    }
    return entry(word)
  }

  /// Returns the phonemes for spelling a word letter by letter, from the dictionary's single-letter entries.
  ///
  /// For example, "PR" is spelled "pˈi ˈɑɹ".
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
      // A doubled consonant, as in "stopped". misaki handles this in stem_ing but not in stem_ed.
      stem = String(word.dropLast(3))
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

  /// The vowels after which an American "t" is pronounced as a flap, as in "water".
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
