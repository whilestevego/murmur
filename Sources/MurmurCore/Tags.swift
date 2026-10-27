import Foundation

/// The tags that set Chatterbox Nano's emotion or speaking style, such as `happy` for `[happy]`.
///
/// They're the names that `--style` accepts.
public let styleTags = [
  "advertisement", "angry", "crying", "dramatic", "fear", "happy", "narration", "sarcastic", "surprised", "whispering",
]

/// The tags that make Chatterbox Nano produce a sound, such as `laugh` for `[laugh]`.
public let soundTags = ["chuckle", "clear throat", "cough", "gasp", "groan", "laugh", "shush", "sigh", "sniff"]

/// Removes Chatterbox Nano's tags from text, along with the spaces before them.
///
/// Kokoro would read a tag aloud. Text in brackets that isn't a tag, such as "[1]", is left alone.
///
/// - Parameter text: The text to clean.
/// - Returns: The text without tags.
public func withoutTags(_ text: String) -> String {
  replace(text, #"\h*\[(?:"# + (styleTags + soundTags).joined(separator: "|") + #")\]"#) { _ in "" }
}

/// Returns a sentence as Chatterbox Nano reads it best.
///
/// A sentence that has none of the ``styleTags`` of its own starts with the style. Decimals are written out digit by
/// digit, because Chatterbox Nano reads "3.14" as "three point one fourteen". For example, "3.14" becomes
/// "3 point 1 4".
///
/// - Parameters:
///   - sentence: A normalized sentence.
///   - style: One of the ``styleTags``, or `nil` for no style.
/// - Returns: The sentence to render.
public func nanoSentence(_ sentence: String, style: String?) -> String {
  let ownStyle = styleTags.contains { sentence.contains("[\($0)]") }
  let styled = ownStyle ? sentence : style.map { "[\($0)] \(sentence)" } ?? sentence
  return replace(styled, #"(?<![\w.])(\d+)\.(\d+)(?![\w]|\.\d)"#) { g in
    "\(g[1]) point " + g[2].map(String.init).joined(separator: " ")
  }
}

/// Splits a sentence that's too long to render in one piece into two halves.
///
/// It splits at the comma nearest the middle, or at the space nearest the middle if there's no comma. It never splits
/// inside a tag. A style tag that starts the sentence starts both halves, so that both keep the style.
///
/// - Parameter sentence: The sentence to split.
/// - Returns: The two halves, or `nil` if the sentence has no comma or space to split at.
public func halves(_ sentence: String) -> (String, String)? {
  let tag = styleTags.first { sentence.hasPrefix("[\($0)] ") }.map { "[\($0)] " } ?? ""
  let body = Array(sentence.dropFirst(tag.count))
  var depth = 0
  var commas: [Int] = []
  var spaces: [Int] = []
  for (i, c) in body.enumerated() {
    if c == "[" { depth += 1 }
    if c == "]" { depth = max(0, depth - 1) }
    if depth == 0 && c == "," { commas.append(i + 1) }
    if depth == 0 && c == " " { spaces.append(i) }
  }
  let middle = body.count / 2
  let cuts = (commas.isEmpty ? spaces : commas).filter { $0 > 0 && $0 < body.count }
  guard let cut = cuts.min(by: { abs($0 - middle) < abs($1 - middle) }) else { return nil }
  let first = String(body[..<cut]).trimmingCharacters(in: .whitespaces)
  let second = String(body[cut...]).trimmingCharacters(in: .whitespaces)
  guard !first.isEmpty, !second.isEmpty else { return nil }
  return (tag + first, tag + second)
}
