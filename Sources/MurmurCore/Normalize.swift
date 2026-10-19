import Foundation

/// Tech text rewritten into words Kokoro reads well, before your respellings. FluidAudio already reads plain numbers
/// (`26`, `3.14`, `13th`) but leaves the ambiguous forms alone, and those come out as "ex": grouped numbers, clock
/// times, versions, units, numbers glued to letters. Links, paths and code names get the same treatment. `knows` says
/// whether a word has a known pronunciation, so `GitHub`-style names are split into words only when it doesn't.
public func normalize(_ text: String, knows: (String) -> Bool = { _ in false }) -> String {
  var t = text
  // Curly quotes: a curly apostrophe (it’s) is read as a separate "s".
  t = t.replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{2018}", with: "'")
  t = t.replacingOccurrences(of: "\u{201C}", with: "\"").replacingOccurrences(of: "\u{201D}", with: "\"")

  // https://github.com/a/b → "github dot com"
  t = replace(t, "https?://(?:www\\.)?([A-Za-z0-9.-]+?)(?:[/?#:][^\\s]*?)?(?=[.,;:!?)\\]]*(?:\\s|$))") {
    $0[1].replacingOccurrences(of: ".", with: " dot ")
  }
  // ~/src/app/main.swift → "main dot swift"; and/or and client/server stay.
  t = replace(t, "(?<![\\w/.~-])(~|\\.{1,2})?(/)?((?:[\\w.-]+/)+)([\\w-]+(?:\\.[\\w-]+)*)") { g in
    let hasType = g[4].contains(".") && spokenExtension(String(g[4].split(separator: ".").last!)) != nil
    let isPath = !g[1].isEmpty || !g[2].isEmpty || g[3].filter { $0 == "/" }.count > 1 || hasType
    return isPath ? g[4] : nil
  }
  // plugin.json → "plugin dot jason", register.tsx → "register dot T S X"
  t = replace(t, "\\b([\\w-]+)\\.([A-Za-z0-9]+)\\b") { g in spokenExtension(g[2]).map { "\(g[1]) dot \($0)" } }

  // v1.2.3 → "version 1 point 2 point 3"; 0.15.5 → "0 point 15 point 5"
  t = replace(t, "\\bv(\\d+(?:\\.\\d+)*)\\b") { "version " + $0[1].replacingOccurrences(of: ".", with: " point ") }
  t = replace(t, "\\b\\d+(?:\\.\\d+){2,}\\b") { $0[0].replacingOccurrences(of: ".", with: " point ") }
  // 2026-10-19 → "October 19, 2026"
  t = replace(t, "\\b(\\d{4})-(\\d{2})-(\\d{2})\\b") { g in
    guard let m = Int(g[2]), let d = Int(g[3]), (1...12).contains(m), (1...31).contains(d) else { return nil }
    return "\(months[m - 1]) \(d), \(g[1])"
  }
  // 1,000 → 1000
  t = replace(t, "(?<![\\d.,])\\d{1,3}(?:,\\d{3})+(?:\\.\\d+)?(?![\\d,])") { $0[0].replacingOccurrences(of: ",", with: "") }
  // $5 → "5 dollars", $5.50 → "5 dollars and 50 cents", $2M → "2 million dollars"
  t = replace(t, "([$€£])(\\d+)(?:\\.(\\d{2}))?(?:\\s?(k|K|M|B|million|billion)\\b)?") { g in
    let (one, many, cent, cents) = g[1] == "$" ? ("dollar", "dollars", "cent", "cents") : g[1] == "€" ? ("euro", "euros", "cent", "cents") : ("pound", "pounds", "penny", "pence")
    if !g[4].isEmpty {
      let scale = ["k": "thousand", "K": "thousand", "M": "million", "B": "billion"][g[4]] ?? g[4]
      return "\(g[2])\(g[3].isEmpty ? "" : " point \(g[3])") \(scale) \(many)"
    }
    let whole = g[2] == "1" ? "1 \(one)" : "\(g[2]) \(many)"
    guard let c = Int(g[3]), c > 0 else { return whole }
    let change = c == 1 ? "1 \(cent)" : "\(c) \(cents)"
    return g[2] == "0" ? change : "\(whole) and \(change)"
  }
  // 50% → "50 percent"
  t = replace(t, "(\\d)\\s?%") { "\($0[1]) percent" }
  // 10:30 → "10 30", 3:05 → "3 oh 5", 9:00 → "9 o'clock"; FluidAudio reads 1:49 PM itself.
  t = replace(t, "(?<![\\d:])([01]?\\d|2[0-3]):([0-5]\\d)(?![\\d:])(?!\\s*[AaPp]\\.?[Mm]\\b)") { g in
    g[2] == "00" ? "\(g[1]) o'clock" : g[2].hasPrefix("0") ? "\(g[1]) oh \(g[2].dropFirst())" : "\(g[1]) \(g[2])"
  }
  // 10–20 and 10-20 → "10 to 20"; -3 → "minus 3"
  t = replace(t, "(\\d)\\s?[–—]\\s?(?=\\d)") { "\($0[1]) to " }
  t = replace(t, "(?<![\\w.-])(\\d+)-(\\d+)(?![\\w-])") { "\($0[1]) to \($0[2])" }
  t = replace(t, "(?<![\\w)\\]])-(?=\\d)") { _ in "minus " }
  // 200ms → "200 milliseconds", 1 MB → "1 megabyte", 2x → "2 times"
  t = replace(t, "(?<![\\w.])(\\d+(?:\\.\\d+)?)(?:\\s?(\(units.keys.sorted { $0.count > $1.count }.joined(separator: "|")))|(\(gluedUnits.keys.joined(separator: "|"))))(?![\\w/])") { g in
    let unit = g[2].isEmpty ? gluedUnits[g[3]]! : units[g[2]]!
    return "\(g[1]) \(g[1] == "1" ? unit.0 : unit.1)"
  }
  // H264 → "H 264", but 21st stays.
  t = replace(t, "\\b(?=[A-Za-z]*\\d)(?=\\d*[A-Za-z])[A-Za-z0-9]+\\b") { g in
    if g[0].range(of: "^\\d+(st|nd|rd|th)$", options: .regularExpression) != nil { return nil }
    return replace(g[0], "(?<=[A-Za-z])(?=\\d)|(?<=\\d)(?=[A-Za-z])") { _ in " " }
  }

  // Symbols Kokoro skips or misreads.
  for (symbol, words) in symbols { t = t.replacingOccurrences(of: symbol, with: words) }
  t = replace(t, "(?<=\\s)&(?=\\s)") { _ in "and" }
  t = replace(t, "~(?=\\d)") { _ in "about " }
  t = replace(t, "#(\\d+)") { "number \($0[1])" }

  // snake_case → "snake case"; setVoiceName → "set Voice Name", unless the whole name has a pronunciation.
  t = replace(t, "(?<=[A-Za-z0-9])_+(?=[A-Za-z0-9])") { _ in " " }
  t = replace(t, "\\b[A-Za-z]*(?:[a-z][A-Z]|[A-Z][A-Z][a-z])[A-Za-z]*\\b") { g in
    if knows(g[0]) || g[0].range(of: "^[A-Z]+s$", options: .regularExpression) != nil { return nil }
    return replace(g[0], "(?<=[a-z])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])") { _ in " " }
  }
  return t
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

private let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
private let units: [String: (String, String)] = [
  "ms": ("millisecond", "milliseconds"), "µs": ("microsecond", "microseconds"), "ns": ("nanosecond", "nanoseconds"),
  "sec": ("second", "seconds"), "secs": ("second", "seconds"), "min": ("minute", "minutes"), "mins": ("minute", "minutes"),
  "hr": ("hour", "hours"), "hrs": ("hour", "hours"),
  "KB": ("kilobyte", "kilobytes"), "kB": ("kilobyte", "kilobytes"), "MB": ("megabyte", "megabytes"),
  "GB": ("gigabyte", "gigabytes"), "TB": ("terabyte", "terabytes"),
  "px": ("pixel", "pixels"), "pt": ("point", "points"), "fps": ("frame per second", "frames per second"),
  "Hz": ("hertz", "hertz"), "kHz": ("kilohertz", "kilohertz"), "MHz": ("megahertz", "megahertz"), "GHz": ("gigahertz", "gigahertz"),
]
/// Only right after the number (5s, 2x, 3h): spaced out, these are too often a word.
private let gluedUnits: [String: (String, String)] = [
  "s": ("second", "seconds"), "m": ("minute", "minutes"), "h": ("hour", "hours"), "x": ("time", "times"),
]
private let symbols: [(String, String)] = [
  ("→", " to "), ("->", " to "), ("≥", " at least "), (">=", " at least "), ("≤", " at most "), ("<=", " at most "),
  ("≠", " not equal to "), ("!=", " not equal to "), ("==", " equals "), ("±", " plus or minus "), ("×", " times "),
]

/// Each match of `pattern` replaced by `f` of its groups (0 is the whole match, a missing group ""); nil keeps it.
func replace(_ text: String, _ pattern: String, _ f: ([String]) -> String?) -> String {
  guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
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
