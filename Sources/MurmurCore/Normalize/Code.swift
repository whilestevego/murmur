import Foundation

/// Returns how a file extension is spoken.
///
/// Some extensions are read as words, such as "json" as "jason". Others are spelled out, such as "tsx" as "T S X".
///
/// - Parameter ext: The extension, without the dot.
/// - Returns: The spoken form, or `nil` if the extension isn't one murmur knows.
func spokenExtension(_ ext: String) -> String? {
  let ext = ext.lowercased()
  if let word = [
    "json": "jason", "yaml": "yamel", "yml": "yamel", "toml": "tommel", "go": "go", "swift": "swift",
    "lock": "lock", "log": "log", "java": "java", "env": "env", "plist": "P list", "jpeg": "J peg", "jpg": "J peg",
  ][ext] {
    return word
  }
  let lettered: Set<String> = [
    "md", "ts", "tsx", "js", "jsx", "mjs", "cjs", "py", "rb", "rs", "sh", "zsh", "css", "scss", "html", "txt",
    "sql", "csv", "xml", "wav", "mp3", "mp4", "png", "gif", "svg", "pdf", "kt", "cpp",
  ]
  return lettered.contains(ext) ? ext.uppercased().map(String.init).joined(separator: " ") : nil
}

/// Replaces file paths with the file's name.
///
/// For example, "~/src/app/main.swift" becomes "main.swift", which ``fileNames(_:)`` then reads as "main dot swift".
/// Word pairs such as "and/or" and "client/server" aren't paths, so they're left for the slash rule.
func paths(_ text: String) -> String {
  replace(text, #"(?<![\w/.~-])(~|\.{1,2})?(/)?((?:[\w.-]+/)+)([\w-]+(?:\.[\w-]+)*)"#) { g in
    let hasType = g[4].contains(".") && g[4].split(separator: ".").last.flatMap { spokenExtension(String($0)) } != nil
    let isPath = !g[1].isEmpty || !g[2].isEmpty || g[3].filter { $0 == "/" }.count > 2 || hasType
    return isPath && g[0].contains(where: \.isLetter) ? g[4] : nil
  }
}

/// Reads the extensions of file names aloud.
///
/// For example, "plugin.json" becomes "plugin dot jason", and "register.tsx" becomes "register dot T S X".
func fileNames(_ text: String) -> String {
  replace(text, #"\b([\w-]+)\.([A-Za-z0-9]+)\b"#) { g in spokenExtension(g[2]).map { "\(g[1]) dot \($0)" } }
}

/// Reads version numbers aloud.
///
/// For example, "v1.2.3" becomes "version 1 point 2 point 3", and "0.15.5" becomes "0 point 15 point 5".
func versions(_ text: String) -> String {
  let t = replace(text, #"\bv(\d+(?:\.\d+)*)\b"#) { "version " + $0[1].replacingOccurrences(of: ".", with: " point ") }
  return replace(t, #"\b\d+(?:\.\d+){2,}\b"#) { $0[0].replacingOccurrences(of: ".", with: " point ") }
}

/// Reads dotted names aloud, with "dot" between the parts.
///
/// For example, "process.env" becomes "process dot env". The abbreviations "e.g." and "i.e." are left alone.
func dottedNames(_ text: String) -> String {
  replace(text, #"(?<![\w.@])([a-z][\w-]*(?:\.[a-z][\w-]*)+)(?![\w.]|\.\w)"#) { g in
    ["e.g", "i.e"].contains(g[1]) ? nil : g[1].replacingOccurrences(of: ".", with: " dot ")
  }
}

/// Separates the letters and digits in codes.
///
/// For example, "covid-19" becomes "covid 19", "7-eleven" becomes "7 eleven", and "H264" becomes "H 264". Ordinals
/// such as "21st" are left alone.
func mixedCodes(_ text: String) -> String {
  let t = replace(text, #"(?<=[A-Za-z])-(?=\d)|(?<=\d)-(?=[A-Za-z])"#) { _ in " " }
  return replace(t, #"\b(?=[A-Za-z]*\d)(?=\d*[A-Za-z])[A-Za-z0-9]+\b"#) { g in
    let digits = g[0].prefix { $0.isNumber }
    if let n = Int(digits), g[0].dropFirst(digits.count).lowercased() == ordinalSuffix(n) { return nil }
    let split = replace(g[0], #"(?<=[A-Za-z])(?=\d)|(?<=\d)(?=[A-Za-z])"#) { _ in " " }
    // Read a code's run of four or more digits one by one, as in "ab9453". A round number, as in "t2000", stays a number.
    return replace(split, #"\d{4,}"#) { $0[0].hasSuffix("00") ? nil : spaced($0[0]) }
  }
}

/// Splits identifiers into words.
///
/// For example, "snake_case" becomes "snake case", and "setVoiceName" becomes "set Voice Name". A camel-case name that
/// `knows` recognizes is left alone, because it has its own pronunciation.
func identifiers(_ text: String, knows: (String) -> Bool) -> String {
  let t = replace(text, #"(?<=[A-Za-z0-9])_+(?=[A-Za-z0-9])"#) { _ in " " }
  return replace(t, #"\b[A-Za-z]*(?:[a-z][A-Z]|[A-Z][A-Z][a-z])[A-Za-z]*\b"#) { g in
    if knows(g[0]) || g[0].range(of: "^[A-Z]+s$", options: .regularExpression) != nil { return nil }
    return replace(g[0], #"(?<=[a-z])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])"#) { _ in " " }
  }
}
