import Foundation

// MARK: - Numbers in text

/// Reads "401(k)" as "4 oh 1 k".
func fourOhOneK(_ text: String) -> String {
  replace(text, #"\b401\([kK]\)"#) { _ in "4 oh 1 k" }
}

/// Reads quarters and eras aloud.
///
/// For example, "2Q22" becomes "the second quarter of 22", and "340 A.D" becomes "3 40 AD".
func quartersAndEras(_ text: String) -> String {
  let t = replace(text, #"\b([1-4])Q(\d{2}|\d{4})\b"#) { g in
    Int(g[1]).map { "the \(ordinalWords($0)) quarter of \(g[2])" }
  }
  return replace(t, #"\b(\d{1,4})\h?(A\.?D|B\.?C)\b\.?"#) { "\(houseNumber($0[1])) \($0[2].filter(\.isLetter))" }
}

/// Reads numbers that are too large for FluidAudio.
///
/// A number of 13 or more digits without commas is read digit by digit. A number with seven or more comma groups,
/// such as "124,444,234,854,823,834,553", is read in words.
func bigNumbers(_ text: String) -> String {
  let t = replace(text, #"(?<![\d.,])\d{13,}(?![\d.,]\d|\d)"#) { spaced($0[0]) }
  return replace(t, #"(?<![\d.,])\d{1,3}(?:,\d{3}){6,}(?![\d,])"#) { g in
    let groups = g[0].split(separator: ",").compactMap { Int($0) }
    let scales = [
      "", "thousand", "million", "billion", "trillion", "quadrillion", "quintillion", "sextillion", "septillion",
    ]
    guard groups.count < scales.count else { return nil }
    return groups.enumerated().compactMap { i, n in
      n == 0 ? nil : "\(cardinalWords(n)) \(scales[groups.count - 1 - i])"
    }.joined(separator: " ")
  }
}

/// Removes the commas from numbers such as "1,000", so that they're read as one number.
func thousandsCommas(_ text: String) -> String {
  replace(text, #"(?<![\d.,])\d{1,3}(?:,\d{3})+(?:\.\d+)?(?![\d,])"#) { $0[0].replacingOccurrences(of: ",", with: "") }
}

/// Reads leading decimal points and percent signs aloud.
///
/// For example, ".25" becomes "point 2 5", and "50%" becomes "50 percent".
func pointsAndPercents(_ text: String) -> String {
  let t = replace(text, #"(?<![\w.])\.(\d+)\b"#) { "point \(spaced($0[1]))" }
  return replace(t, #"(\d)\h?%"#) { "\($0[1]) percent" }
}

/// Reads arithmetic aloud.
///
/// Minus and division signs are read as math only in an expression with an equals sign, as in "1-2=5", which becomes
/// "1 minus 2 equals 5". Elsewhere, "2x3" becomes "2 by 3", and "1+2" becomes "1 plus 2".
func math(_ text: String) -> String {
  var t = replace(text, #"[\w.]+(?:\h?[-+*/]\h?[\w.]+)*\h?=\h?[\w.]+(?:\h?[-+*/]\h?[\w.]+)*"#) { g in
    let ops = ["-": " minus ", "+": " plus ", "*": " times ", "/": " over ", "=": " equals "]
    let said = g[0].map { ops[String($0)] ?? String($0) }.joined()
    return said.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
  }
  t = replace(t, #"(\d)\h?x\h?(?=\d)"#) { "\($0[1]) by " }
  return replace(t, #"(?<=\d)\h?\+\h?(?=\d)"#) { _ in " plus " }
}

/// Reads number ranges and negative numbers aloud.
///
/// For example, "10-20" and "10–20" become "10 to 20", and "-3" becomes "minus 3".
func ranges(_ text: String) -> String {
  var t = replace(text, #"(\d)\h?[–—]\h?(?=\d)"#) { "\($0[1]) to " }
  t = replace(t, #"(?<![\w.-])(\d+(?:\.\d+)?)-(\d+(?:\.\d+)?)(?![\d-])"#) { "\($0[1]) to \($0[2])" }
  return replace(t, #"(?<![\w)\]])-(?=\.?\d)"#) { _ in "minus " }
}

/// Reads Roman numerals after words such as "Chapter" as numbers.
///
/// For example, "Chapter IV" becomes "Chapter 4".
func romanChapters(_ text: String) -> String {
  replace(
    text,
    #"(?i)\b(chapter|part|section|volume|vol\.|book|act|scene|phase|stage|level|world war|article|appendix|title)\h+([IVXLC]+)\b"#
  ) { g in
    roman(g[2]).map { "\(g[1]) \($0)" }
  }
}

// MARK: - Money, fractions, decades, years

/// Reads amounts of money aloud.
func money(_ text: String) -> String {
  var t = replace(text, #"(?<=\d)\h?-\h?(?=(?:US\$|[$€£¥₩])\d)"#) { _ in " to " }
  // For example, "$20.50" becomes "20 dollars 50 cents", "$2.5 million" becomes "2.5 million dollars", and "$20/mo"
  // becomes "20 dollars per month".
  let pattern =
    #"(US\$|[$€£¥₩])\h?(\d*)(?:\.(\d+))?(?:\h?(thousand|million|billion|trillion|bn|mn|[kKmMbB])\b)?(?:/(mo|month|yr|year|wk|week|d|day|hr|hour|h)\b)?"#
  t = replace(t, pattern) { g in
    guard !(g[2] + g[3]).isEmpty, let c = currencies[g[1]] else { return nil }
    let per = periods[g[5]].map { " per \($0)" } ?? ""
    if !g[4].isEmpty {
      let scale = scales[g[4]] ?? g[4]
      return "\(g[2].isEmpty ? "0" : g[2])\(g[3].isEmpty ? "" : ".\(g[3])") \(scale) \(c.many)\(per)"
    }
    let whole = Int(g[2].isEmpty ? "0" : g[2]) ?? 0
    var cents = g[3]
    if cents.count > 2 {
      guard cents.dropFirst(2).allSatisfy({ $0 == "0" }) else { return "\(g[2]).\(cents) \(c.many)\(per)" }
      cents = String(cents.prefix(2))
    }
    if cents.count == 1 { cents += "0" }
    let amount = "\(whole) \(whole == 1 ? c.one : c.many)"
    guard let n = Int(cents), n > 0 else { return amount + per }
    let change = "\(n) \(n == 1 ? c.cent : c.cents)"
    return (whole == 0 ? change : "\(amount) \(change)") + per
  }
  return t
}

private let currencies: [String: (one: String, many: String, cent: String, cents: String)] = [
  "$": ("dollar", "dollars", "cent", "cents"), "US$": ("us dollar", "us dollars", "cent", "cents"),
  "€": ("euro", "euros", "cent", "cents"), "£": ("pound", "pounds", "penny", "pence"),
  "¥": ("yen", "yen", "sen", "sen"), "₩": ("won", "won", "jeon", "jeon"),
]
private let scales = [
  "k": "thousand", "K": "thousand", "m": "million", "M": "million", "mn": "million",
  "b": "billion", "B": "billion", "bn": "billion",
]
private let periods = [
  "mo": "month", "month": "month", "yr": "year", "year": "year", "wk": "week", "week": "week",
  "d": "day", "day": "day", "hr": "hour", "hour": "hour", "h": "hour",
]

/// Reads fractions aloud.
func fractions(_ text: String) -> String {
  var t = text
  // For example, "2 1/2" becomes "2 and a half".
  t = replace(t, #"(?i)(?<![\d/.])(\d+)\h+(\d+)/(\d+)(?:st|nd|rd|th)?(?![\w/])"#) { g in
    fraction(g[2], g[3], mixed: true).map { "\(g[1]) and \($0)" }
  }
  // For example, "1/4" becomes "1 quarter", and "31/32" becomes "31 thirty seconds". The phrase "24/7" is read as
  // "24 7".
  t = replace(t, #"(?i)(?<![\d/.:])(\d+)\h?/\h?(\d+)(?:st|nd|rd|th)?(?![\w/])"#) { g in
    g[0] == "24/7" ? "24 7" : fraction(g[1], g[2], mixed: false)
  }
  return replace(t, #"(?<=\d)/(?=\d)"#) { _ in " slash " }
}

private func fraction(_ n: String, _ d: String, mixed: Bool) -> String? {
  guard let num = Int(n), let den = Int(d), den > 0 else { return nil }
  let one = num == 1
  switch den {
  case 1: return "\(n) over 1"
  case 2: return one ? (mixed ? "a half" : "1 half") : "\(n) halves"
  case 4: return one ? (mixed ? "a quarter" : "1 quarter") : "\(n) quarters"
  default: return "\(num >= 1000 ? cardinalWords(num) : n) \(ordinalWords(den))\(one ? "" : "s")"
  }
}

/// Reads decades aloud.
///
/// For example, "1980s" becomes "19 eighties", "'80s" becomes "eighties", and "2000s" becomes "two thousands". A range
/// such as "1960s-80s" is read with "to".
func decades(_ text: String) -> String {
  let t = replace(text, #"(?<=\ds)\h?[-–]\h?(?=(?:\d{2}|\d{4})s\b)"#) { _ in " to " }
  return replace(t, #"(?<![\w.])(?:'|(1\d|20))?(\d)0(?:s|(?<=\d{4})\h+s)\b"#) { g in
    let tens = [
      "hundreds", "tens", "twenties", "thirties", "forties", "fifties", "sixties", "seventies", "eighties", "nineties",
    ]
    guard let d = Int(g[2]) else { return nil }
    if g[1] == "20" && d == 0 { return "two thousands" }
    if d == 0 && g[1].isEmpty { return nil }
    return g[1].isEmpty ? tens[d] : "\(g[1]) \(tens[d])"
  }
}

/// Reads years aloud.
///
/// For example, "1994" becomes "19 94", "1906" becomes "19 oh 6", and "1900" becomes "19 hundred". FluidAudio already
/// reads 2000 to 2009 correctly, so those are left alone.
// ponytail: Any number from 1100 to 2099 is read as a year, unless a unit or a plural noun follows it, as in "2048
// tokens". Looking at the surrounding words would catch more cases.
func years(_ text: String) -> String {
  replace(text, yearPattern) { g in
    let y = g[1]
    let (hi, lo) = (y.prefix(2), y.suffix(2))
    if y.hasPrefix("200") || lo == "00" && hi == "20" { return nil }
    if lo == "00" { return "\(hi) hundred" }
    return lo.hasPrefix("0") ? "\(hi) oh \(lo.dropFirst())" : "\(hi) \(lo)"
  }
}

/// The pattern for a year that isn't followed by a unit or a plural noun.
private let yearPattern: String = {
  let named: [(String, String)] = Array(units.values) + Array(gluedUnits.values)
  let unitWords: [String] = named.flatMap { [$0.0, $0.1] } + ["percent"]
  let unitAlternation: String = Set(unitWords).map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
  let notPlural = #"this|was|has|does|is|its|his|thus|yes|plus|less|unless|across|always|perhaps|as|us"#
  let year = #"(?<![\d.,:$€£¥₩#/-])(1[1-9]\d{2}|20\d{2})(?![\d.,:/]\d|\d)"#
  let noUnit = #"(?!(?:\h+to\h+\d+(?:\.\d+)?)?\h+(?:"# + unitAlternation + #")\b)"#
  let noPlural = #"(?!\h+(?!(?:"# + notPlural + #")\b)[a-z]{2,}s\b)"#
  return year + noUnit + noPlural
}()

// MARK: - Words for numbers, extensions and symbols

private let spellOut: NumberFormatter = {
  let f = NumberFormatter()
  f.numberStyle = .spellOut
  f.locale = Locale(identifier: "en_US")
  return f
}()

/// Returns a number in words, such as "thirty two" for 32.
func cardinalWords(_ n: Int) -> String {
  (spellOut.string(from: n as NSNumber) ?? "\(n)").replacingOccurrences(of: "-", with: " ")
}

/// Returns a number as ordinal words.
///
/// For example, 32 becomes "thirty second".
func ordinalWords(_ n: Int) -> String {
  var words = cardinalWords(n).split(separator: " ").map(String.init)
  let last = words.removeLast()
  let irregular = [
    "one": "first", "two": "second", "three": "third", "five": "fifth", "eight": "eighth", "nine": "ninth",
    "twelve": "twelfth",
  ]
  words.append(irregular[last] ?? (last.hasSuffix("y") ? last.dropLast() + "ieth" : last + "th"))
  return words.joined(separator: " ")
}

/// Returns the ordinal suffix for a number, such as "st" for 1 and "th" for 11.
func ordinalSuffix(_ n: Int) -> String {
  if (11...13).contains(n % 100) { return "th" }
  return [1: "st", 2: "nd", 3: "rd"][n % 10] ?? "th"
}

/// Returns digits separated by spaces, so that they're read one by one.
///
/// For example, "123" becomes "1 2 3".
func spaced(_ digits: String) -> String { digits.map(String.init).joined(separator: " ") }

/// Returns the value of a Roman numeral.
///
/// - Parameter s: A Roman numeral, such as "IV".
/// - Returns: The value, or `nil` if the string is empty or has a character other than I, V, X, L and C.
func roman(_ s: String) -> Int? {
  let values: [Character: Int] = ["I": 1, "V": 5, "X": 10, "L": 50, "C": 100]
  let digits = s.compactMap { values[$0] }
  guard digits.count == s.count, !digits.isEmpty else { return nil }
  var total = 0
  for (i, v) in digits.enumerated() { total += i + 1 < digits.count && v < digits[i + 1] ? -v : v }
  return total
}
