import Foundation
import os

/// Rewrites text into words that Kokoro reads well.
///
/// FluidAudio already reads plain numbers (`26`, `3.14`, `13th`) but leaves the ambiguous forms alone, and those come
/// out as "ex" or garbled. The rules follow NVIDIA NeMo's English text normalization, checked against its test cases
/// (`Tests/nemo`, `make nemo`). Further rules cover text from code, such as paths, file names, versions, `snake_case`
/// and `camelCase`. Normalization runs before respellings are applied.
///
/// - Parameters:
///   - text: The text to normalize.
///   - knows: Returns whether a word has a known pronunciation. Camel-case names such as "GitHub" are split into words
///     only when it returns `false`.
/// - Returns: The normalized text.
public func normalize(_ text: String, knows: (String) -> Bool = { _ in false }) -> String {
  withoutActuallyEscaping(knows) { knows in steps(knows).reduce(text) { t, step in step.apply(t) } }
}

/// Returns normalization's steps, in the order they run.
///
/// Each step works on the output of the steps before it, so the order matters.
private func steps(_ knows: @escaping (String) -> Bool) -> [(name: String, apply: (String) -> String)] {
  [
    ("straightQuotes", straightQuotes),
    ("fourOhOneK", fourOhOneK),
    // This runs before versions, so that "123.123.0.40" is read as an IP address and not a version.
    ("electronic", electronic),
    ("fileLinks", fileLinks),
    ("dates", dates),
    ("paths", paths),
    ("fileNames", fileNames),
    ("versions", versions),
    ("times", times),
    ("dottedNames", dottedNames),
    ("quartersAndEras", quartersAndEras),
    ("bigNumbers", bigNumbers),
    // This runs before money, so that "$1,000" is read as one amount.
    ("thousandsCommas", thousandsCommas),
    ("money", money),
    ("pointsAndPercents", pointsAndPercents),
    ("fractions", fractions),
    ("decades", decades),
    ("symbolWords", symbolWords),
    ("math", math),
    ("ranges", ranges),
    ("measures", measures),
    ("addresses", addresses),
    ("years", years),
    ("mixedCodes", mixedCodes),
    ("romanChapters", romanChapters),
    ("loneSymbols", loneSymbols),
    ("identifiers", { identifiers($0, knows: knows) }),
    // This runs last, so that it also sees the numbers that the other steps write, such as "number 1234".
    ("yearlikeNumbers", yearlikeNumbers),
    ("squeezeSpaces", squeezeSpaces),
  ]
}

private func straightQuotes(_ text: String) -> String {
  // Kokoro reads the "s" after a curly apostrophe, as in "it’s", as a separate word.
  text.replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{2018}", with: "'")
    .replacingOccurrences(of: "\u{201C}", with: "\"").replacingOccurrences(of: "\u{201D}", with: "\"")
}

private func symbolWords(_ text: String) -> String {
  symbols.reduce(text) { t, s in t.replacingOccurrences(of: s.0, with: s.1) }
}

/// Reads symbols as words when they stand alone.
private func loneSymbols(_ text: String) -> String {
  var t = replace(text, #"\+\+"#) { _ in " plus plus" }
  t = replace(t, #"(?<=\h)&(?=\h)"#) { _ in "and" }
  t = replace(t, #"~(?=\d)"#) { _ in "about " }
  t = replace(t, #"#(\d+)"#) { "number \($0[1])" }
  t = replace(t, #"(?<=\d)\h?\*\h?(?=\d)"#) { _ in " times " }
  let names = [
    "$": "dollar", "€": "euro", "£": "pound", "¥": "yen", "₩": "won", "%": "percent", "#": "hash", "@": "at",
    "&": "and",
  ]
  t = replace(t, #"[$€£¥₩%#@&]"#) { g in names[g[0]].map { " \($0) " } }
  t = replace(t, #"(?<!\S)/(?!\w)"#) { _ in " slash " }
  // A slash between words is read as "slash", as in "upgrade slash update". The exception is "and/or", read as "and or".
  return replace(t, #"\b([A-Za-z]+)\h?/\h?(?=[A-Za-z])"#) { g in
    g[1].lowercased() == "and" ? "and " : "\(g[1]) slash "
  }
}

private func squeezeSpaces(_ text: String) -> String {
  text.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
}

private let symbols: [(String, String)] = [
  ("→", " to "), ("->", " to "), ("≥", " at least "), (">=", " at least "), ("≤", " at most "), ("<=", " at most "),
  ("≠", " not equal to "), ("!=", " not equal to "), ("==", " equals "), ("±", " plus or minus "), ("×", " times "),
]

/// The compiled regular expressions, by pattern.
///
/// Each pattern is compiled once, the first time it's used.
private let compiled = OSAllocatedUnfairLock(initialState: [String: NSRegularExpression]())

/// Replaces each match of a regular expression.
///
/// - Parameters:
///   - text: The text to search.
///   - pattern: The regular expression. `^` and `$` match at the start and end of each line.
///   - f: Returns the replacement for a match, given its capture groups. Group 0 is the whole match, and a group that
///     didn't match is an empty string. Returning `nil` leaves the match unchanged.
/// - Returns: The text with the matches replaced.
func replace(_ text: String, _ pattern: String, _ f: ([String]) -> String?) -> String {
  // Patterns use \h, never \s. A line break ends a sentence, so no rule may match across one.
  let regex = compiled.withLock { cache in
    if let regex = cache[pattern] { return regex }
    // swift-format-ignore: NeverUseForceTry
    // Every pattern is a constant, so a mistake in one fails every test.
    let regex = try! NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)
    cache[pattern] = regex
    return regex
  }
  let source = text as NSString
  var out = ""
  var last = 0
  for m in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
    let groups = (0..<m.numberOfRanges).map {
      m.range(at: $0).location == NSNotFound ? "" : source.substring(with: m.range(at: $0))
    }
    out += source.substring(with: NSRange(location: last, length: m.range.location - last))
    out += f(groups) ?? groups[0]
    last = m.range.location + m.range.length
  }
  return out + source.substring(from: last)
}
