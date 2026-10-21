import Foundation

// MARK: - Dates and times

/// Reads dates aloud.
func dates(_ text: String) -> String {
  var t = text
  // For example, "2026-10-19" becomes "October 19th 2026".
  t = replace(t, #"\b(\d{4})-(\d{2})-(\d{2})\b"#) { g in date(month: g[2], day: g[3], year: g[1]) }
  // Numeric dates such as "10/06/2005" are read in American order, month first. When the first number can't be a
  // month, as in "15.01.2020", it's read as the day. The next rule handles year-first dates such as "1998/2/30".
  t = replace(t, #"(?<![\d/.-])(\d{1,2})([/.-])(\d{1,2})\2(\d{4}|\d{2})(?![\d/.-])"#) { g in
    if g[2] != "/" && g[4].count == 2 { return nil }
    if let first = Int(g[1]), first > 12, let m = Int(g[3]), (1...12).contains(m) {
      return "the \(first)\(ordinalSuffix(first)) of \(months[m - 1]) \(g[4])"
    }
    return date(month: g[1], day: g[3], year: g[4])
  }
  t = replace(t, #"(?<![\d/])(\d{4})/(\d{1,2})/(\d{1,2})(?![\d/])"#) { g in date(month: g[2], day: g[3], year: g[1]) }
  // For example, "July 25 2012" becomes "July 25th 2012", and "SEPT. 15" becomes "September 15th".
  t = replace(
    t, "(?i)\\b\(monthPattern)\\.?(?:\\h+|-)(\\d{1,2})(?:st|nd|rd|th)?\\b(?![:.]\\d)(?:(?:,?\\h+|-)(\\d{4})\\b)?"
  ) { g in
    // In lowercase, "may" and "march" are usually verbs, as in "we may 5 times". They're read as months only when a
    // year follows.
    if ["may", "march"].contains(g[1]) && g[3].isEmpty { return nil }
    guard let m = month(g[1]), let d = Int(g[2]), (1...31).contains(d) else { return nil }
    return "\(m) \(d)\(ordinalSuffix(d))" + (g[3].isEmpty ? "" : " \(g[3])")
  }
  // For example, "25 july 2012" becomes "the 25th of July 2012", and "the 26th May" becomes "the 26th of May".
  t = replace(
    t, "(?i)\\b(?:the\\h+)?(\\d{1,2})(?:st|nd|rd|th)?\\h+(?:of\\h+)?\(monthPattern)\\b\\.?(?:,?\\h+(\\d{4})\\b)?"
  ) { g in
    guard let m = month(g[2]), let d = Int(g[1]), (1...31).contains(d) else { return nil }
    return "the \(d)\(ordinalSuffix(d)) of \(m)" + (g[3].isEmpty ? "" : " \(g[3])")
  }
  return t
}

private let monthPattern =
  "(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sept?(?:ember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)"
private let months = [
  "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November",
  "December",
]

private func month(_ name: String) -> String? {
  let key = name.lowercased().prefix(3)
  return months.first { $0.lowercased().hasPrefix(key) }
}

private func date(month m: String, day d: String, year y: String) -> String? {
  guard let m = Int(m), let d = Int(d), (1...12).contains(m), (1...31).contains(d) else { return nil }
  return "\(months[m - 1]) \(d)\(ordinalSuffix(d)) \(y)"
}

/// Reads times of day and durations aloud.
func times(_ text: String) -> String {
  var t = text
  // For example, "1:01:01" becomes "1 hour 1 minute and 1 second".
  t = replace(t, #"(?i)(?<![\d:])(\d{1,2}):([0-5]\d):([0-5]\d)(?![\d:])(\h*[ap]\.?m\b\.?)?"#) { g in
    guard let h = Int(g[1]), let m = Int(g[2]), let s = Int(g[3]) else { return nil }
    let said =
      "\(h) \(h == 1 ? "hour" : "hours") \(m) \(m == 1 ? "minute" : "minutes") and \(s) \(s == 1 ? "second" : "seconds")"
    return said + (g[4].isEmpty ? "" : " \(meridiem(g[4]))")
  }
  // For example, "1:59 p.m." becomes "1 59 PM", "01:00 am" becomes "1 AM", and "2pm" becomes "2 PM".
  t = replace(t, #"(?i)(?<![\d:.])(\d{1,2})(?:[:.]([0-5]\d))?\h?([ap])\.?m\b\.?"#) { g in
    guard let h = Int(g[1]), (0...12).contains(h) else { return nil }
    return "\(h)\(g[2].isEmpty || g[2] == "00" ? "" : " \(minutes(g[2]))") \(meridiem(g[3]))"
  }
  // Time zones are read as letters, so "1:59 PM e.s.t" becomes "1 59 PM EST". A range such as "5 PM-7 PM" becomes
  // "5 PM to 7 PM".
  t = replace(t, #"(?i)\b(AM|PM)\h*([ecmp])\.?([sd])\.?t\b\.?"#) {
    "\($0[1]) \($0[2].uppercased())\($0[3].uppercased())T"
  }
  t = replace(t, #"\b(AM|PM)\h?[-–]\h?(?=\d)"#) { "\($0[1]) to " }
  // For example, "10:30" becomes "10 30", "3:05" becomes "3 oh 5", and "09:00" becomes "9 o'clock".
  t = replace(t, #"(?<![\d:])([01]?\d|2[0-3]):([0-5]\d)(?![\d:])"#) { g in
    guard let h = Int(g[1]) else { return nil }
    return g[2] == "00" ? "\(h) o'clock" : "\(h) \(minutes(g[2]))"
  }
  return t
}

private func meridiem(_ s: String) -> String { s.lowercased().contains("p") ? "PM" : "AM" }
private func minutes(_ m: String) -> String { m.hasPrefix("0") ? "oh \(m.dropFirst())" : m }
