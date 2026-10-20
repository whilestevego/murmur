import Foundation

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
