import Foundation

// MARK: - Numbers in text

func fourOhOneK(_ text: String) -> String {
  replace(text, #"\b401\([kK]\)"#) { _ in "4 oh 1 k" }
}

// 2Q22 → "the second quarter of 22"; 340 A.D → "3 40 AD"
func quartersAndEras(_ text: String) -> String {
  let t = replace(text, #"\b([1-4])Q(\d{2}|\d{4})\b"#) { "the \(ordinalWords(Int($0[1])!)) quarter of \($0[2])" }
  return replace(t, #"\b(\d{1,4})\h?(A\.?D|B\.?C)\b\.?"#) { "\(houseNumber($0[1])) \($0[2].filter(\.isLetter))" }
}

// 1234567890123124 → digit by digit; 124,444,234,854,823,834,553 → words, past what FluidAudio counts to.
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

// 1,000 → 1000
func thousandsCommas(_ text: String) -> String {
  replace(text, #"(?<![\d.,])\d{1,3}(?:,\d{3})+(?:\.\d+)?(?![\d,])"#) { $0[0].replacingOccurrences(of: ",", with: "") }
}

// .25 → "point 2 5"; 50% → "50 percent"
func pointsAndPercents(_ text: String) -> String {
  let t = replace(text, #"(?<![\w.])\.(\d+)\b"#) { "point \(spaced($0[1]))" }
  return replace(t, #"(\d)\h?%"#) { "\($0[1]) percent" }
}

// 1-2=5 → "1 minus 2 equals 5": operators read as math only around an equals sign. 2x3 → "2 by 3", 1+2 → "1 plus 2"
func math(_ text: String) -> String {
  var t = replace(text, #"[\w.]+(?:\h?[-+*/]\h?[\w.]+)*\h?=\h?[\w.]+(?:\h?[-+*/]\h?[\w.]+)*"#) { g in
    let ops = ["-": " minus ", "+": " plus ", "*": " times ", "/": " over ", "=": " equals "]
    let said = g[0].map { ops[String($0)] ?? String($0) }.joined()
    return said.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
  }
  t = replace(t, #"(\d)\h?x\h?(?=\d)"#) { "\($0[1]) by " }
  return replace(t, #"(?<=\d)\h?\+\h?(?=\d)"#) { _ in " plus " }
}

// 10–20 and 10-20 → "10 to 20"; -3 → "minus 3"
func ranges(_ text: String) -> String {
  var t = replace(text, #"(\d)\h?[–—]\h?(?=\d)"#) { "\($0[1]) to " }
  t = replace(t, #"(?<![\w.-])(\d+(?:\.\d+)?)-(\d+(?:\.\d+)?)(?![\d-])"#) { "\($0[1]) to \($0[2])" }
  return replace(t, #"(?<![\w)\]])-(?=\.?\d)"#) { _ in "minus " }
}

// Chapter IV → "Chapter 4"
func romanChapters(_ text: String) -> String {
  replace(
    text,
    #"(?i)\b(chapter|part|section|volume|vol\.|book|act|scene|phase|stage|level|world war|article|appendix|title)\h+([IVXLC]+)\b"#
  ) { g in
    roman(g[2]).map { "\(g[1]) \($0)" }
  }
}

// MARK: - Money, fractions, decades, years

func money(_ text: String) -> String {
  var t = replace(text, #"(?<=\d)\h?-\h?(?=(?:US\$|[$€£¥₩])\d)"#) { _ in " to " }
  // $5 → "5 dollars", $20.50 → "20 dollars 50 cents", $2.5 million → "2.5 million dollars", $20/mo → "… per month"
  let pattern =
    #"(US\$|[$€£¥₩])\h?(\d*)(?:\.(\d+))?(?:\h?(thousand|million|billion|trillion|bn|mn|[kKmMbB])\b)?(?:/(mo|month|yr|year|wk|week|d|day|hr|hour|h)\b)?"#
  t = replace(t, pattern) { g in
    guard !(g[2] + g[3]).isEmpty else { return nil }
    let c = currencies[g[1]]!
    let per = g[5].isEmpty ? "" : " per \(periods[g[5]]!)"
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

func fractions(_ text: String) -> String {
  var t = text
  // 2 1/2 → "2 and a half"
  t = replace(t, #"(?i)(?<![\d/.])(\d+)\h+(\d+)/(\d+)(?:st|nd|rd|th)?(?![\w/])"#) { g in
    fraction(g[2], g[3], mixed: true).map { "\(g[1]) and \($0)" }
  }
  // 1/4 → "1 quarter", 31/32 → "31 thirty seconds"; 24/7 stays.
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

func decades(_ text: String) -> String {
  // 1960s-80s → "1960s to 80s"; 1980s → "19 eighties", '80s → "eighties", 2000s → "two thousands"
  let t = replace(text, #"(?<=\ds)\h?[-–]\h?(?=(?:\d{2}|\d{4})s\b)"#) { _ in " to " }
  return replace(t, #"(?<![\w.])(?:'|(1\d|20))?(\d)0(?:s|(?<=\d{4})\h+s)\b"#) { g in
    let tens = [
      "hundreds", "tens", "twenties", "thirties", "forties", "fifties", "sixties", "seventies", "eighties", "nineties",
    ]
    let d = Int(g[2])!
    if g[1] == "20" && d == 0 { return "two thousands" }
    if d == 0 && g[1].isEmpty { return nil }
    return g[1].isEmpty ? tens[d] : "\(g[1]) \(tens[d])"
  }
}

/// 1994 → "19 94", 2012 → "20 12", 1906 → "19 oh 6", 1900 → "19 hundred"; 2000–2009 FluidAudio reads itself.
/// ponytail: any 1100–2099 reads as a year unless a unit or a plural noun follows (2048 tokens); context would do better.
func years(_ text: String) -> String {
  replace(text, yearPattern) { g in
    let y = g[1]
    let (hi, lo) = (y.prefix(2), y.suffix(2))
    if y.hasPrefix("200") || lo == "00" && hi == "20" { return nil }
    if lo == "00" { return "\(hi) hundred" }
    return lo.hasPrefix("0") ? "\(hi) oh \(lo.dropFirst())" : "\(hi) \(lo)"
  }
}

/// A year, unless a unit or a plural noun follows it.
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

func cardinalWords(_ n: Int) -> String {
  (spellOut.string(from: n as NSNumber) ?? "\(n)").replacingOccurrences(of: "-", with: " ")
}

/// 32 → "thirty second", 2007 → "two thousand seventh"
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

func ordinalSuffix(_ n: Int) -> String {
  if (11...13).contains(n % 100) { return "th" }
  return [1: "st", 2: "nd", 3: "rd"][n % 10] ?? "th"
}

/// "123" → "1 2 3", read digit by digit.
func spaced(_ digits: String) -> String { digits.map(String.init).joined(separator: " ") }

/// IV → 4; nil for anything that isn't a well-formed numeral.
func roman(_ s: String) -> Int? {
  let values: [Character: Int] = ["I": 1, "V": 5, "X": 10, "L": 50, "C": 100]
  let digits = s.compactMap { values[$0] }
  guard digits.count == s.count, !digits.isEmpty else { return nil }
  var total = 0
  for (i, v) in digits.enumerated() { total += i + 1 < digits.count && v < digits[i + 1] ? -v : v }
  return total
}
