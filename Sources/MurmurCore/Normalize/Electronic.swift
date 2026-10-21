import Foundation

// MARK: - Links, emails, phone numbers

/// Reads email addresses, links, IP addresses and phone numbers aloud.
func electronic(_ text: String) -> String {
  var t = text
  // For example, "a.bc@gmail.com" becomes "a dot bc at gmail dot com".
  t = replace(t, #"(?<![\w.+-])([\w.+&-]+)@([\w-]+(?:\.[\w-]+)+)((?:/[\w.-]*)*)"#) { g in
    "\(spokenAddress(g[1])) at \(spokenDomain(g[2]))\(spokenPath(g[3]))"
  }
  // Only a link's host is read, because a whole link is too long to follow when spoken. For example,
  // "https://www.example.com/a/b" becomes "WWW dot example dot com".
  t = replace(t, #"(?i)\b(?:https?|ftp)://([\w.-]+?)(?::\d+)?(?:[/?#][^\h]*?)?(?=[.,;:!?)\]]*(?:\h|$))"#) {
    spokenDomain($0[1])
  }
  // A bare domain is read with its path. For example, "example.com/12-sm" becomes "example dot com slash 1 2 dash sm".
  t = replace(
    t,
    #"(?<![\w@./-])((?:[\w-]+\.)+(?i:com|org|net|edu|gov|io|ai|dev|app|co|uk|de|fr|it|sm|us|ca|jp|au|info|biz))\b((?:/[\w.-]*)*)"#
  ) { g in
    "\(spokenDomain(g[1]))\(spokenPath(g[2]))"
  }
  // IP addresses are read digit by digit. For example, "123.123.0.40" becomes "1 2 3 dot 1 2 3 dot 0 dot 4 0".
  t = replace(t, #"\b(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\b"#) { g in
    g[1...4].map(spaced).joined(separator: " dot ")
  }
  // Phone numbers are read digit by digit, with a pause between groups. For example, "+1 (123) 123-5678" becomes
  // "plus 1, 1 2 3, 1 2 3, 5 6 7 8". The last rule reads numbers such as "111-11-1111" the same way.
  t = replace(
    t, #"(?<![\w+])(?:\+(\d{1,3})[\h-]?)?(?:\((\d{3})\)|(\d{3}))[\h.-]?(\d{3})[\h.-](\d{4})((?:-\d+)?)(?![\w-])"#
  ) { g in
    let parts = [g[2] + g[3], g[4], g[5]] + (g[6].isEmpty ? [] : [String(g[6].dropFirst())])
    return (g[1].isEmpty ? "" : "plus \(g[1]), ") + parts.map(spaced).joined(separator: ", ")
  }
  t = replace(t, #"\b(\d{3})-(\d{2})-(\d{4})\b"#) { g in g[1...3].map(spaced).joined(separator: ", ") }
  return t
}

/// The top-level domains that are read as words.
///
/// Other domains, such as "uk", are spelled out.
private let wordTLDs: Set<String> = ["com", "org", "net", "edu", "gov", "info", "biz", "app", "dev"]

/// Returns a host name as it's spoken, with "dot" between its labels.
private func spokenDomain(_ host: String) -> String {
  let labels = host.split(separator: ".").map(String.init)
  return labels.enumerated().map { i, label in
    if label.lowercased() == "www" { return "WWW" }
    if i == labels.count - 1 && i > 0 && !wordTLDs.contains(label.lowercased()) { return label.uppercased() }
    return spokenAddress(label)
  }.joined(separator: " dot ")
}

/// Returns part of an address or path as it's spoken.
///
/// Punctuation is read by name, and digits are read one by one.
private func spokenAddress(_ s: String) -> String {
  let names: [Character: String] = [
    ".": "dot", "-": "dash", "_": "underscore", "&": "ampersand", "+": "plus", "/": "slash",
  ]
  var out: [String] = []
  var word = ""
  for c in s {
    if let name = names[c] {
      if !word.isEmpty {
        out.append(word)
        word = ""
      }
      out.append(name)
    } else if c.isNumber {
      if !word.isEmpty {
        out.append(word)
        word = ""
      }
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

/// Removes the `file://` scheme from links, so that the path rules see a plain path.
func fileLinks(_ text: String) -> String {
  replace(text, #"(?i)\bfile://"#) { _ in "" }
}
