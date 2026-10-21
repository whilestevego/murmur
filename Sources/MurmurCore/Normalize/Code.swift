import Foundation

/// How a file extension is said: "jason", "swift", or its letters ("T S X"); nil for anything that isn't one.
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

// ~/src/app/main.swift → "main dot swift"; and/or and client/server are left to the slash rule.
func paths(_ text: String) -> String {
  replace(text, #"(?<![\w/.~-])(~|\.{1,2})?(/)?((?:[\w.-]+/)+)([\w-]+(?:\.[\w-]+)*)"#) { g in
    let hasType = g[4].contains(".") && g[4].split(separator: ".").last.flatMap { spokenExtension(String($0)) } != nil
    let isPath = !g[1].isEmpty || !g[2].isEmpty || g[3].filter { $0 == "/" }.count > 2 || hasType
    return isPath && g[0].contains(where: \.isLetter) ? g[4] : nil
  }
}

// plugin.json → "plugin dot jason", register.tsx → "register dot T S X"
func fileNames(_ text: String) -> String {
  replace(text, #"\b([\w-]+)\.([A-Za-z0-9]+)\b"#) { g in spokenExtension(g[2]).map { "\(g[1]) dot \($0)" } }
}

// v1.2.3 → "version 1 point 2 point 3"; 0.15.5 → "0 point 15 point 5"
func versions(_ text: String) -> String {
  let t = replace(text, #"\bv(\d+(?:\.\d+)*)\b"#) { "version " + $0[1].replacingOccurrences(of: ".", with: " point ") }
  return replace(t, #"\b\d+(?:\.\d+){2,}\b"#) { $0[0].replacingOccurrences(of: ".", with: " point ") }
}

// process.env, test.abc → "process dot env"; e.g. and i.e. stay.
func dottedNames(_ text: String) -> String {
  replace(text, #"(?<![\w.@])([a-z][\w-]*(?:\.[a-z][\w-]*)+)(?![\w.]|\.\w)"#) { g in
    ["e.g", "i.e"].contains(g[1]) ? nil : g[1].replacingOccurrences(of: ".", with: " dot ")
  }
}

// covid-19 → "covid 19", 7-eleven → "7 eleven"; H264 → "H 264", but 21st stays.
func mixedCodes(_ text: String) -> String {
  let t = replace(text, #"(?<=[A-Za-z])-(?=\d)|(?<=\d)-(?=[A-Za-z])"#) { _ in " " }
  return replace(t, #"\b(?=[A-Za-z]*\d)(?=\d*[A-Za-z])[A-Za-z0-9]+\b"#) { g in
    let digits = g[0].prefix { $0.isNumber }
    if let n = Int(digits), g[0].dropFirst(digits.count).lowercased() == ordinalSuffix(n) { return nil }
    let split = replace(g[0], #"(?<=[A-Za-z])(?=\d)|(?<=\d)(?=[A-Za-z])"#) { _ in " " }
    // ab9453, a code: digit by digit; t2000 stays a number
    return replace(split, #"\d{4,}"#) { $0[0].hasSuffix("00") ? nil : spaced($0[0]) }
  }
}

// snake_case → "snake case"; setVoiceName → "set Voice Name", unless the whole name has a pronunciation.
func identifiers(_ text: String, knows: (String) -> Bool) -> String {
  let t = replace(text, #"(?<=[A-Za-z0-9])_+(?=[A-Za-z0-9])"#) { _ in " " }
  return replace(t, #"\b[A-Za-z]*(?:[a-z][A-Z]|[A-Z][A-Z][a-z])[A-Za-z]*\b"#) { g in
    if knows(g[0]) || g[0].range(of: "^[A-Z]+s$", options: .regularExpression) != nil { return nil }
    return replace(g[0], #"(?<=[a-z])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])"#) { _ in " " }
  }
}
