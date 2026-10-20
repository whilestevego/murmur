import Foundation
import os

/// Text rewritten into words Kokoro reads well, before your respellings. FluidAudio already reads plain numbers (`26`,
/// `3.14`, `13th`) but leaves the ambiguous forms alone, and those come out as "ex" or garbled. The rules follow NVIDIA
/// NeMo's English text normalization, checked against its test cases (`Tests/nemo`, `make nemo`), plus what code adds:
/// paths, file names, versions, `snake_case` and `camelCase`. `knows` says whether a word has a known pronunciation,
/// so `GitHub`-style names are split into words only when it doesn't.
public func normalize(_ text: String, knows: (String) -> Bool = { _ in false }) -> String {
  withoutActuallyEscaping(knows) { knows in steps(knows).reduce(text) { t, step in step.apply(t) } }
}

/// The steps in the order they run: each reads what the steps before it wrote.
private func steps(_ knows: @escaping (String) -> Bool) -> [(name: String, apply: (String) -> String)] {
  [
    ("straightQuotes", straightQuotes),
    ("fourOhOneK", fourOhOneK),
    // Before versions: 123.123.0.40 is an IP address, not a version.
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
    // Before money: $1,000 is one amount.
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
    ("squeezeSpaces", squeezeSpaces),
  ]
}

private func straightQuotes(_ text: String) -> String {
  // Curly quotes: a curly apostrophe (it’s) is read as a separate "s".
  text.replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{2018}", with: "'")
    .replacingOccurrences(of: "\u{201C}", with: "\"").replacingOccurrences(of: "\u{201D}", with: "\"")
}

private func symbolWords(_ text: String) -> String {
  symbols.reduce(text) { t, s in t.replacingOccurrences(of: s.0, with: s.1) }
}

/// Symbols said as words when they stand alone.
private func loneSymbols(_ text: String) -> String {
  var t = replace(text, #"\+\+"#) { _ in " plus plus" }
  t = replace(t, #"(?<=\h)&(?=\h)"#) { _ in "and" }
  t = replace(t, #"~(?=\d)"#) { _ in "about " }
  t = replace(t, #"#(\d+)"#) { "number \($0[1])" }
  t = replace(t, #"(?<=\d)\h?\*\h?(?=\d)"#) { _ in " times " }
  let names = ["$": "dollar", "€": "euro", "£": "pound", "¥": "yen", "₩": "won", "%": "percent", "#": "hash", "@": "at", "&": "and"]
  t = replace(t, #"[$€£¥₩%#@&]"#) { g in names[g[0]].map { " \($0) " } }
  t = replace(t, #"(?<!\S)/(?!\w)"#) { _ in " slash " }
  // upgrade/update → "upgrade slash update"; and/or → "and or"
  return replace(t, #"\b([A-Za-z]+)\h?/\h?(?=[A-Za-z])"#) { g in g[1].lowercased() == "and" ? "and " : "\(g[1]) slash " }
}

private func squeezeSpaces(_ text: String) -> String {
  text.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
}

private let symbols: [(String, String)] = [
  ("→", " to "), ("->", " to "), ("≥", " at least "), (">=", " at least "), ("≤", " at most "), ("<=", " at most "),
  ("≠", " not equal to "), ("!=", " not equal to "), ("==", " equals "), ("±", " plus or minus "), ("×", " times "),
]

/// Each pattern compiled once, on first use.
private let compiled = OSAllocatedUnfairLock(initialState: [String: NSRegularExpression]())

/// Each match of `pattern` replaced by `f` of its groups (0 is the whole match, a missing group ""); nil keeps it.
func replace(_ text: String, _ pattern: String, _ f: ([String]) -> String?) -> String {
  // Patterns use \h, never \s: a line break ends a sentence, so no rule may span one, and ^ and $ match at each line.
  // The patterns are constants, so a bad one fails every test.
  let regex = compiled.withLock { cache in
    if let regex = cache[pattern] { return regex }
    let regex = try! NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)
    cache[pattern] = regex
    return regex
  }
  let source = text as NSString
  var out = ""
  var last = 0
  for m in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
    let groups = (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : source.substring(with: m.range(at: $0)) }
    out += source.substring(with: NSRange(location: last, length: m.range.location - last))
    out += f(groups) ?? groups[0]
    last = m.range.location + m.range.length
  }
  return out + source.substring(from: last)
}
