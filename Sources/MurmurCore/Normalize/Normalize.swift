import Foundation
import os

/// Text rewritten into words Kokoro reads well, before your respellings. FluidAudio already reads plain numbers (`26`,
/// `3.14`, `13th`) but leaves the ambiguous forms alone, and those come out as "ex" or garbled. The rules follow NVIDIA
/// NeMo's English text normalization, checked against its test cases (`Tests/nemo`, `make nemo`), plus what code adds:
/// paths, file names, versions, `snake_case` and `camelCase`. `knows` says whether a word has a known pronunciation,
/// so `GitHub`-style names are split into words only when it doesn't.
public func normalize(_ text: String, knows: (String) -> Bool = { _ in false }) -> String {
  var t = text
  // Curly quotes: a curly apostrophe (it’s) is read as a separate "s".
  t = t.replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{2018}", with: "'")
  t = t.replacingOccurrences(of: "\u{201C}", with: "\"").replacingOccurrences(of: "\u{201D}", with: "\"")
  t = replace(t, #"\b401\([kK]\)"#) { _ in "4 oh 1 k" }

  t = electronic(t)
  t = replace(t, #"(?i)\bfile://"#) { _ in "" }
  t = dates(t)
  // ~/src/app/main.swift → "main dot swift"; and/or and client/server are left to the slash rule below.
  t = replace(t, #"(?<![\w/.~-])(~|\.{1,2})?(/)?((?:[\w.-]+/)+)([\w-]+(?:\.[\w-]+)*)"#) { g in
    let hasType = g[4].contains(".") && spokenExtension(String(g[4].split(separator: ".").last!)) != nil
    let isPath = !g[1].isEmpty || !g[2].isEmpty || g[3].filter { $0 == "/" }.count > 2 || hasType
    return isPath && g[0].contains(where: \.isLetter) ? g[4] : nil
  }
  // plugin.json → "plugin dot jason", register.tsx → "register dot T S X"
  t = replace(t, #"\b([\w-]+)\.([A-Za-z0-9]+)\b"#) { g in spokenExtension(g[2]).map { "\(g[1]) dot \($0)" } }
  // v1.2.3 → "version 1 point 2 point 3"; 0.15.5 → "0 point 15 point 5"
  t = replace(t, #"\bv(\d+(?:\.\d+)*)\b"#) { "version " + $0[1].replacingOccurrences(of: ".", with: " point ") }
  t = replace(t, #"\b\d+(?:\.\d+){2,}\b"#) { $0[0].replacingOccurrences(of: ".", with: " point ") }
  t = times(t)
  // process.env, test.abc → "process dot env"; e.g. and i.e. stay.
  t = replace(t, #"(?<![\w.@])([a-z][\w-]*(?:\.[a-z][\w-]*)+)(?![\w.]|\.\w)"#) { g in
    ["e.g", "i.e"].contains(g[1]) ? nil : g[1].replacingOccurrences(of: ".", with: " dot ")
  }
  // 2Q22 → "the second quarter of 22"; 340 A.D → "3 40 AD"
  t = replace(t, #"\b([1-4])Q(\d{2}|\d{4})\b"#) { "the \(ordinalWords(Int($0[1])!)) quarter of \($0[2])" }
  t = replace(t, #"\b(\d{1,4})\h?(A\.?D|B\.?C)\b\.?"#) { "\(houseNumber($0[1])) \($0[2].filter(\.isLetter))" }
  // 1234567890123124 → digit by digit; 124,444,234,854,823,834,553 → words, past what FluidAudio counts to.
  t = replace(t, #"(?<![\d.,])\d{13,}(?![\d.,]\d|\d)"#) { spaced($0[0]) }
  t = replace(t, #"(?<![\d.,])\d{1,3}(?:,\d{3}){6,}(?![\d,])"#) { g in
    let groups = g[0].split(separator: ",").compactMap { Int($0) }
    let scales = ["", "thousand", "million", "billion", "trillion", "quadrillion", "quintillion", "sextillion", "septillion"]
    guard groups.count < scales.count else { return nil }
    return groups.enumerated().compactMap { i, n in
      n == 0 ? nil : "\(cardinalWords(n)) \(scales[groups.count - 1 - i])"
    }.joined(separator: " ")
  }
  // 1,000 → 1000
  t = replace(t, #"(?<![\d.,])\d{1,3}(?:,\d{3})+(?:\.\d+)?(?![\d,])"#) { $0[0].replacingOccurrences(of: ",", with: "") }
  t = money(t)
  // .25 → "point 2 5"
  t = replace(t, #"(?<![\w.])\.(\d+)\b"#) { "point \(spaced($0[1]))" }
  t = replace(t, #"(\d)\h?%"#) { "\($0[1]) percent" }
  t = fractions(t)
  t = replace(t, #"(?<=\d)/(?=\d)"#) { _ in " slash " }
  t = decades(t)

  for (symbol, words) in symbols { t = t.replacingOccurrences(of: symbol, with: words) }
  // 1-2=5 → "1 minus 2 equals 5": operators read as math only around an equals sign.
  t = replace(t, #"[\w.]+(?:\h?[-+*/]\h?[\w.]+)*\h?=\h?[\w.]+(?:\h?[-+*/]\h?[\w.]+)*"#) { g in
    let ops = ["-": " minus ", "+": " plus ", "*": " times ", "/": " over ", "=": " equals "]
    return g[0].map { ops[String($0)] ?? String($0) }.joined().replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
  }
  t = replace(t, #"(\d)\h?x\h?(?=\d)"#) { "\($0[1]) by " }
  t = replace(t, #"(?<=\d)\h?\+\h?(?=\d)"#) { _ in " plus " }
  // 10–20 and 10-20 → "10 to 20"; -3 → "minus 3"
  t = replace(t, #"(\d)\h?[–—]\h?(?=\d)"#) { "\($0[1]) to " }
  t = replace(t, #"(?<![\w.-])(\d+(?:\.\d+)?)-(\d+(?:\.\d+)?)(?![\d-])"#) { "\($0[1]) to \($0[2])" }
  t = replace(t, #"(?<![\w)\]])-(?=\.?\d)"#) { _ in "minus " }
  t = measures(t)
  t = addresses(t)
  t = years(t)

  // covid-19 → "covid 19", 7-eleven → "7 eleven"; H264 → "H 264", but 21st stays.
  t = replace(t, #"(?<=[A-Za-z])-(?=\d)|(?<=\d)-(?=[A-Za-z])"#) { _ in " " }
  t = replace(t, #"\b(?=[A-Za-z]*\d)(?=\d*[A-Za-z])[A-Za-z0-9]+\b"#) { g in
    let digits = g[0].prefix { $0.isNumber }
    if let n = Int(digits), g[0].dropFirst(digits.count).lowercased() == ordinalSuffix(n) { return nil }
    let split = replace(g[0], #"(?<=[A-Za-z])(?=\d)|(?<=\d)(?=[A-Za-z])"#) { _ in " " }
    return replace(split, #"\d{4,}"#) { $0[0].hasSuffix("00") ? nil : spaced($0[0]) }  // ab9453, a code: digit by digit; t2000 stays a number
  }
  // Chapter IV → "Chapter 4"
  t = replace(t, #"(?i)\b(chapter|part|section|volume|vol\.|book|act|scene|phase|stage|level|world war|article|appendix|title)\h+([IVXLC]+)\b"#) { g in
    roman(g[2]).map { "\(g[1]) \($0)" }
  }

  // Symbols said as words when they stand alone.
  t = replace(t, #"\+\+"#) { _ in " plus plus" }
  t = replace(t, #"(?<=\h)&(?=\h)"#) { _ in "and" }
  t = replace(t, #"~(?=\d)"#) { _ in "about " }
  t = replace(t, #"#(\d+)"#) { "number \($0[1])" }
  t = replace(t, #"(?<=\d)\h?\*\h?(?=\d)"#) { _ in " times " }
  let names = ["$": "dollar", "€": "euro", "£": "pound", "¥": "yen", "₩": "won", "%": "percent", "#": "hash", "@": "at", "&": "and"]
  t = replace(t, #"[$€£¥₩%#@&]"#) { g in names[g[0]].map { " \($0) " } }
  t = replace(t, #"(?<!\S)/(?!\w)"#) { _ in " slash " }
  // upgrade/update → "upgrade slash update"; and/or → "and or"
  t = replace(t, #"\b([A-Za-z]+)\h?/\h?(?=[A-Za-z])"#) { g in g[1].lowercased() == "and" ? "and " : "\(g[1]) slash " }

  // snake_case → "snake case"; setVoiceName → "set Voice Name", unless the whole name has a pronunciation.
  t = replace(t, #"(?<=[A-Za-z0-9])_+(?=[A-Za-z0-9])"#) { _ in " " }
  t = replace(t, #"\b[A-Za-z]*(?:[a-z][A-Z]|[A-Z][A-Z][a-z])[A-Za-z]*\b"#) { g in
    if knows(g[0]) || g[0].range(of: "^[A-Z]+s$", options: .regularExpression) != nil { return nil }
    return replace(g[0], #"(?<=[a-z])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])"#) { _ in " " }
  }
  return t.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
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
