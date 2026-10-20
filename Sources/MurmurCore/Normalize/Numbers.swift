import Foundation

// MARK: - Money, fractions, decades, years

func money(_ text: String) -> String {
  var t = replace(text, #"(?<=\d)\h?-\h?(?=(?:US\$|[$€£¥₩])\d)"#) { _ in " to " }
  // $5 → "5 dollars", $20.50 → "20 dollars 50 cents", $2.5 million → "2.5 million dollars", $20/mo → "… per month"
  let pattern = #"(US\$|[$€£¥₩])\h?(\d*)(?:\.(\d+))?(?:\h?(thousand|million|billion|trillion|bn|mn|[kKmMbB])\b)?(?:/(mo|month|yr|year|wk|week|d|day|hr|hour|h)\b)?"#
  t = replace(t, pattern) { g in
    guard !(g[2] + g[3]).isEmpty else { return nil }
    let c = currencies[g[1]]!
    let per = g[5].isEmpty ? "" : " per \(periods[g[5]]!)"
    if !g[4].isEmpty {
      let scale = ["k": "thousand", "K": "thousand", "m": "million", "M": "million", "mn": "million", "b": "billion", "B": "billion", "bn": "billion"][g[4]] ?? g[4]
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
private let periods = ["mo": "month", "month": "month", "yr": "year", "year": "year", "wk": "week", "week": "week",
  "d": "day", "day": "day", "hr": "hour", "hour": "hour", "h": "hour"]

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
  return t
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
    let tens = ["hundreds", "tens", "twenties", "thirties", "forties", "fifties", "sixties", "seventies", "eighties", "nineties"]
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
  let unitAlternation: String = Set(unitWords).map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
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
  var words = (spellOut.string(from: n as NSNumber) ?? "\(n)").replacingOccurrences(of: "-", with: " ").split(separator: " ").map(String.init)
  let last = words.removeLast()
  let irregular = ["one": "first", "two": "second", "three": "third", "five": "fifth", "eight": "eighth", "nine": "ninth", "twelve": "twelfth"]
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
