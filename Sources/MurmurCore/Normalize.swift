import Foundation

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

// MARK: - Links, emails, phone numbers

private func electronic(_ text: String) -> String {
  var t = text
  // a.bc@gmail.com → "a dot bc at gmail dot com"
  t = replace(t, #"(?<![\w.+-])([\w.+&-]+)@([\w-]+(?:\.[\w-]+)+)((?:/[\w.-]*)*)"#) { g in
    "\(spokenAddress(g[1])) at \(spokenDomain(g[2]))\(spokenPath(g[3]))"
  }
  // https://www.example.com/a/b → "WWW dot example dot com": the host only, since a whole link is noise aloud.
  t = replace(t, #"(?i)\b(?:https?|ftp)://([\w.-]+?)(?::\d+)?(?:[/?#][^\h]*?)?(?=[.,;:!?)\]]*(?:\h|$))"#) { spokenDomain($0[1]) }
  // example.com/12-sm → "example dot com slash 1 2 dash sm"
  t = replace(t, #"(?<![\w@./-])((?:[\w-]+\.)+(?i:com|org|net|edu|gov|io|ai|dev|app|co|uk|de|fr|it|sm|us|ca|jp|au|info|biz))\b((?:/[\w.-]*)*)"#) { g in
    "\(spokenDomain(g[1]))\(spokenPath(g[2]))"
  }
  // 123.123.0.40 → "1 2 3 dot 1 2 3 dot 0 dot 4 0"
  t = replace(t, #"\b(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\b"#) { g in g[1...4].map(spaced).joined(separator: " dot ") }
  // +1 (123) 123-5678 → "plus 1, 1 2 3, 1 2 3, 5 6 7 8"; 111-11-1111 likewise.
  t = replace(t, #"(?<![\w+])(?:\+(\d{1,3})[\h-]?)?(?:\((\d{3})\)|(\d{3}))[\h.-]?(\d{3})[\h.-](\d{4})((?:-\d+)?)(?![\w-])"#) { g in
    let parts = [g[2] + g[3], g[4], g[5]] + (g[6].isEmpty ? [] : [String(g[6].dropFirst())])
    return (g[1].isEmpty ? "" : "plus \(g[1]), ") + parts.map(spaced).joined(separator: ", ")
  }
  t = replace(t, #"\b(\d{3})-(\d{2})-(\d{4})\b"#) { g in g[1...3].map(spaced).joined(separator: ", ") }
  return t
}

private let wordTLDs: Set<String> = ["com", "org", "net", "edu", "gov", "info", "biz", "app", "dev"]

private func spokenDomain(_ host: String) -> String {
  let labels = host.split(separator: ".").map(String.init)
  return labels.enumerated().map { i, label in
    if label.lowercased() == "www" { return "WWW" }
    if i == labels.count - 1 && i > 0 && !wordTLDs.contains(label.lowercased()) { return label.uppercased() }
    return spokenAddress(label)
  }.joined(separator: " dot ")
}

/// The words of an address or path piece: punctuation by name, digits one by one.
private func spokenAddress(_ s: String) -> String {
  let names: [Character: String] = [".": "dot", "-": "dash", "_": "underscore", "&": "ampersand", "+": "plus", "/": "slash"]
  var out: [String] = []
  var word = ""
  for c in s {
    if let name = names[c] {
      if !word.isEmpty { out.append(word); word = "" }
      out.append(name)
    } else if c.isNumber {
      if !word.isEmpty { out.append(word); word = "" }
      out.append(String(c))
    } else {
      word.append(c)
    }
  }
  if !word.isEmpty { out.append(word) }
  return out.joined(separator: " ")
}

private func spokenPath(_ path: String) -> String {
  path.isEmpty ? "" : " " + spokenAddress(path)
}

// MARK: - Dates and times

private func dates(_ text: String) -> String {
  var t = text
  // 2026-10-19 → "October 19th 2026"
  t = replace(t, #"\b(\d{4})-(\d{2})-(\d{2})\b"#) { g in date(month: g[2], day: g[3], year: g[1]) }
  // 10/06/2005 (American order; day first when it can't be a month, 15.01.2020) and 1998/2/30
  t = replace(t, #"(?<![\d/.-])(\d{1,2})([/.-])(\d{1,2})\2(\d{4}|\d{2})(?![\d/.-])"#) { g in
    if g[2] != "/" && g[4].count == 2 { return nil }
    if let first = Int(g[1]), first > 12, let m = Int(g[3]), (1...12).contains(m) { return "the \(first)\(ordinalSuffix(first)) of \(months[m - 1]) \(g[4])" }
    return date(month: g[1], day: g[3], year: g[4])
  }
  t = replace(t, #"(?<![\d/])(\d{4})/(\d{1,2})/(\d{1,2})(?![\d/])"#) { g in date(month: g[2], day: g[3], year: g[1]) }
  // July 25 2012, SEPT. 15 → "July 25th 2012", "September 15th"
  t = replace(t, "(?i)\\b\(monthPattern)\\.?(?:\\h+|-)(\\d{1,2})(?:st|nd|rd|th)?\\b(?![:.]\\d)(?:(?:,?\\h+|-)(\\d{4})\\b)?") { g in
    // "we may 5 times": lower-case may and march are verbs unless a year follows.
    if ["may", "march"].contains(g[1]) && g[3].isEmpty { return nil }
    guard let m = month(g[1]), let d = Int(g[2]), (1...31).contains(d) else { return nil }
    return "\(m) \(d)\(ordinalSuffix(d))" + (g[3].isEmpty ? "" : " \(g[3])")
  }
  // 25 july 2012, the 26th May → "the 25th of July 2012"
  t = replace(t, "(?i)\\b(?:the\\h+)?(\\d{1,2})(?:st|nd|rd|th)?\\h+(?:of\\h+)?\(monthPattern)\\b\\.?(?:,?\\h+(\\d{4})\\b)?") { g in
    guard let m = month(g[2]), let d = Int(g[1]), (1...31).contains(d) else { return nil }
    return "the \(d)\(ordinalSuffix(d)) of \(m)" + (g[3].isEmpty ? "" : " \(g[3])")
  }
  return t
}

private let monthPattern = "(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sept?(?:ember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)"
private let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

private func month(_ name: String) -> String? {
  let key = name.lowercased().prefix(3)
  return months.first { $0.lowercased().hasPrefix(key) }
}

private func date(month m: String, day d: String, year y: String) -> String? {
  guard let m = Int(m), let d = Int(d), (1...12).contains(m), (1...31).contains(d) else { return nil }
  return "\(months[m - 1]) \(d)\(ordinalSuffix(d)) \(y)"
}

private func times(_ text: String) -> String {
  var t = text
  // 1:01:01 → "1 hour 1 minute and 1 second"
  t = replace(t, #"(?i)(?<![\d:])(\d{1,2}):([0-5]\d):([0-5]\d)(?![\d:])(\h*[ap]\.?m\b\.?)?"#) { g in
    let (h, m, s) = (Int(g[1])!, Int(g[2])!, Int(g[3])!)
    let said = "\(h) \(h == 1 ? "hour" : "hours") \(m) \(m == 1 ? "minute" : "minutes") and \(s) \(s == 1 ? "second" : "seconds")"
    return said + (g[4].isEmpty ? "" : " \(meridiem(g[4]))")
  }
  // 1:59 p.m., 01:00 am, 2pm → "1 59 PM", "1 AM", "2 PM"
  t = replace(t, #"(?i)(?<![\d:.])(\d{1,2})(?:[:.]([0-5]\d))?\h?([ap])\.?m\b\.?"#) { g in
    guard let h = Int(g[1]), (0...12).contains(h) else { return nil }
    return "\(h)\(g[2].isEmpty || g[2] == "00" ? "" : " \(minutes(g[2]))") \(meridiem(g[3]))"
  }
  // 1:59 PM e.s.t → "1 59 PM EST"; 5 PM-7 PM → "5 PM to 7 PM"
  t = replace(t, #"(?i)\b(AM|PM)\h*([ecmp])\.?([sd])\.?t\b\.?"#) { "\($0[1]) \($0[2].uppercased())\($0[3].uppercased())T" }
  t = replace(t, #"\b(AM|PM)\h?[-–]\h?(?=\d)"#) { "\($0[1]) to " }
  // 10:30 → "10 30", 3:05 → "3 oh 5", 09:00 → "9 o'clock"
  t = replace(t, #"(?<![\d:])([01]?\d|2[0-3]):([0-5]\d)(?![\d:])"#) { g in
    let h = Int(g[1])!
    return g[2] == "00" ? "\(h) o'clock" : "\(h) \(minutes(g[2]))"
  }
  return t
}

private func meridiem(_ s: String) -> String { s.lowercased().contains("p") ? "PM" : "AM" }
private func minutes(_ m: String) -> String { m.hasPrefix("0") ? "oh \(m.dropFirst())" : m }

// MARK: - Money, fractions, decades, years

private func money(_ text: String) -> String {
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

private func fractions(_ text: String) -> String {
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

private func decades(_ text: String) -> String {
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
private func years(_ text: String) -> String {
  let named: [(String, String)] = Array(units.values) + Array(gluedUnits.values)
  let unitWords: [String] = named.flatMap { [$0.0, $0.1] } + ["percent"]
  let unitAlternation: String = Set(unitWords).map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
  let notPlural = #"this|was|has|does|is|its|his|thus|yes|plus|less|unless|across|always|perhaps|as|us"#
  let year = #"(?<![\d.,:$€£¥₩#/-])(1[1-9]\d{2}|20\d{2})(?![\d.,:/]\d|\d)"#
  let noUnit = #"(?!(?:\h+to\h+\d+(?:\.\d+)?)?\h+(?:"# + unitAlternation + #")\b)"#
  let noPlural = #"(?!\h+(?!(?:"# + notPlural + #")\b)[a-z]{2,}s\b)"#
  let pattern = year + noUnit + noPlural
  return replace(text, pattern) { g in
    let y = g[1]
    let (hi, lo) = (y.prefix(2), y.suffix(2))
    if y.hasPrefix("200") || lo == "00" && hi == "20" { return nil }
    if lo == "00" { return "\(hi) hundred" }
    return lo.hasPrefix("0") ? "\(hi) oh \(lo.dropFirst())" : "\(hi) \(lo)"
  }
}

// MARK: - Measures and addresses

private func measures(_ text: String) -> String {
  let keys = units.keys.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
  let glued = gluedUnits.keys.joined(separator: "|")
  var t = text
  // 2°C → "2 degrees Celsius"
  t = replace(t, #"(\d+(?:\.\d+)?)\h?[°º]\h?([CF])?\b"#) { g in
    let deg = g[1] == "1" ? "degree" : "degrees"
    return "\(g[1]) \(deg)" + (g[2].isEmpty ? "" : g[2] == "C" ? " Celsius" : " Fahrenheit")
  }
  // 5 m2, 41459 km³ → "5 square meters", "41459 cubic kilometers"
  t = replace(t, #"(\d+(?:\.\d+)?)\h?(km|cm|mm|m|ft)(2|²|3|³)(?!\w)"#) { g in
    let name = ["km": "kilometers", "cm": "centimeters", "mm": "millimeters", "m": "meters", "ft": "feet"][g[2]]!
    return "\(g[1]) \("2²".contains(g[3]) ? "square" : "cubic") \(name)"
  }
  // 12kg/kg, 60 km/h → "per kilogram", "per hour"
  t = replace(t, "(?<=[\\w])\\h?/\\h?(\(keys)|\(glued))(?![\\w/])") { g in
    " per \((units[g[1]] ?? gluedUnits[g[1]])!.0)"
  }
  // 200ms → "200 milliseconds", 100 million kg → "100 million kilograms", 2 and a half lbs → "… pounds"
  t = replace(t, "(?<![\\w.])(\\d+(?:\\.\\d+)?)((?:\\h(?:thousand|million|billion|trillion))?)(?:\\h?(\(keys))|(\(glued)))(?![\\w/])") { g in
    let unit = g[3].isEmpty ? gluedUnits[g[4]]! : units[g[3]]!
    return "\(g[1])\(g[2]) \(g[1] == "1" && g[2].isEmpty ? unit.0 : unit.1)"
  }
  t = replace(t, "\\b(half|halves|quarters?|thirds?)\\h+(\(keys))(?![\\w/])") { "\($0[1]) \(units[$0[2]]!.1)" }
  return t
}

private let units: [String: (String, String)] = [
  "ms": ("millisecond", "milliseconds"), "µs": ("microsecond", "microseconds"), "ns": ("nanosecond", "nanoseconds"),
  "sec": ("second", "seconds"), "secs": ("second", "seconds"), "min": ("minute", "minutes"), "mins": ("minute", "minutes"),
  "hr": ("hour", "hours"), "hrs": ("hour", "hours"),
  "KB": ("kilobyte", "kilobytes"), "kB": ("kilobyte", "kilobytes"), "MB": ("megabyte", "megabytes"),
  "GB": ("gigabyte", "gigabytes"), "TB": ("terabyte", "terabytes"),
  "kbps": ("kilobit per second", "kilobits per second"), "Kbps": ("kilobit per second", "kilobits per second"),
  "mbps": ("megabit per second", "megabits per second"), "Mbps": ("megabit per second", "megabits per second"),
  "gbps": ("gigabit per second", "gigabits per second"), "Gbps": ("gigabit per second", "gigabits per second"),
  "px": ("pixel", "pixels"), "pt": ("point", "points"), "fps": ("frame per second", "frames per second"),
  "Hz": ("hertz", "hertz"), "kHz": ("kilohertz", "kilohertz"), "MHz": ("megahertz", "megahertz"), "GHz": ("gigahertz", "gigahertz"),
  "kg": ("kilogram", "kilograms"), "KG": ("kilogram", "kilograms"), "mg": ("milligram", "milligrams"),
  "lb": ("pound", "pounds"), "lbs": ("pound", "pounds"), "oz": ("ounce", "ounces"),
  "km": ("kilometer", "kilometers"), "cm": ("centimeter", "centimeters"), "mm": ("millimeter", "millimeters"),
  "ft": ("foot", "feet"), "mph": ("mile per hour", "miles per hour"), "kph": ("kilometer per hour", "kilometers per hour"),
]
/// Only right after the number (5s, 3h, 200g): spaced out, these are too often a word.
private let gluedUnits: [String: (String, String)] = [
  "s": ("second", "seconds"), "m": ("minute", "minutes"), "h": ("hour", "hours"), "g": ("gram", "grams"),
]

private func addresses(_ text: String) -> String {
  let street = ["St": "Street", "Ave": "Avenue", "Rd": "Road", "Ct": "Court", "Blvd": "Boulevard", "Dr": "Drive", "Ln": "Lane",
    "Expy": "Expressway", "Hwy": "Highway", "Pkwy": "Parkway", "Pl": "Place"]
  let way = ["N": "North", "S": "South", "E": "East", "W": "West"]
  // 1428 Elm St, 708 N 1st St → "14 28 Elm Street", "7 0 8 North 1st Street"
  var t = replace(text, #"\b(\d{1,5})\h+(?:([NSEW])\.?\h+)?((?:(?:[A-Z][a-z]+|\d+(?:st|nd|rd|th))\h+){1,3})(?i:(st|ave|rd|ct|blvd|dr|ln|expy|hwy|pkwy|pl))\b"#) { g in
    let kind = street.first { $0.key.lowercased() == g[4].lowercased() }!.value
    return "\(houseNumber(g[1])) \(g[2].isEmpty ? "" : way[g[2]]! + " ")\(g[3])\(kind)"
  }
  // …Street, Santa Clara, CA 95051 → "…, California 9 5 0 5 1"
  t = replace(t, #"((?:Street|Avenue|Road|Court|Boulevard|Drive|Lane|Expressway|Highway|Parkway|Place)(?:,\h+[A-Z][a-z]+(?:\h[A-Z][a-z]+)*)?),\h+([A-Z]{2})\b(,?\h+\d{5})?"#) { g in
    guard let state = states[g[2]] else { return nil }
    return "\(g[1]), \(state)" + (g[3].isEmpty ? "" : (g[3].hasPrefix(",") ? "," : "") + " " + spaced(g[3].filter(\.isNumber)))
  }
  return t
}

/// 1428 → "14 28", 123 → "1 23", 708 → "7 0 8"
private func houseNumber(_ n: String) -> String {
  switch n.count {
  case 3: return n.dropFirst().hasPrefix("0") ? spaced(n) : "\(n.prefix(1)) \(n.suffix(2))"
  case 4: return n.suffix(2).hasPrefix("0") ? n : "\(n.prefix(2)) \(n.suffix(2))"
  default: return n
  }
}

private let states = [
  "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas", "CA": "California", "CO": "Colorado",
  "CT": "Connecticut", "DE": "Delaware", "FL": "Florida", "GA": "Georgia", "HI": "Hawaii", "ID": "Idaho",
  "IL": "Illinois", "IN": "Indiana", "IA": "Iowa", "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine",
  "MD": "Maryland", "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota", "MS": "Mississippi", "MO": "Missouri",
  "MT": "Montana", "NE": "Nebraska", "NV": "Nevada", "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico",
  "NY": "New York", "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio", "OK": "Oklahoma", "OR": "Oregon",
  "PA": "Pennsylvania", "RI": "Rhode Island", "SC": "South Carolina", "SD": "South Dakota", "TN": "Tennessee",
  "TX": "Texas", "UT": "Utah", "VT": "Vermont", "VA": "Virginia", "WA": "Washington", "WV": "West Virginia",
  "WI": "Wisconsin", "WY": "Wyoming", "DC": "D C",
]

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
private func spaced(_ digits: String) -> String { digits.map(String.init).joined(separator: " ") }

/// IV → 4; nil for anything that isn't a well-formed numeral.
func roman(_ s: String) -> Int? {
  let values: [Character: Int] = ["I": 1, "V": 5, "X": 10, "L": 50, "C": 100]
  let digits = s.compactMap { values[$0] }
  guard digits.count == s.count, !digits.isEmpty else { return nil }
  var total = 0
  for (i, v) in digits.enumerated() { total += i + 1 < digits.count && v < digits[i + 1] ? -v : v }
  return total
}

/// How a file extension is said: "jason", "swift", or its letters ("T S X"); nil for anything that isn't one.
func spokenExtension(_ ext: String) -> String? {
  let ext = ext.lowercased()
  if let word = ["json": "jason", "yaml": "yamel", "yml": "yamel", "toml": "tommel", "go": "go", "swift": "swift",
    "lock": "lock", "log": "log", "java": "java", "env": "env", "plist": "P list", "jpeg": "J peg", "jpg": "J peg"][ext]
  {
    return word
  }
  let lettered: Set<String> = [
    "md", "ts", "tsx", "js", "jsx", "mjs", "cjs", "py", "rb", "rs", "sh", "zsh", "css", "scss", "html", "txt",
    "sql", "csv", "xml", "wav", "mp3", "mp4", "png", "gif", "svg", "pdf", "kt", "cpp",
  ]
  return lettered.contains(ext) ? ext.uppercased().map(String.init).joined(separator: " ") : nil
}

private let symbols: [(String, String)] = [
  ("→", " to "), ("->", " to "), ("≥", " at least "), (">=", " at least "), ("≤", " at most "), ("<=", " at most "),
  ("≠", " not equal to "), ("!=", " not equal to "), ("==", " equals "), ("±", " plus or minus "), ("×", " times "),
]

/// Each match of `pattern` replaced by `f` of its groups (0 is the whole match, a missing group ""); nil keeps it.
func replace(_ text: String, _ pattern: String, _ f: ([String]) -> String?) -> String {
  // Patterns use \h, never \s: a line break ends a sentence, so no rule may span one, and ^ and $ match at each line.
  // The patterns are constants, so a bad one fails every test.
  let regex = try! NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)
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
