import Foundation

/// Returns the share of a sentence that a transcript of its render gets wrong.
///
/// The comparison uses only letters and digits, and ignores case. A respelling therefore matches its transcript. For
/// example, "M C P" matches "MCP". A render of the sentence scores near 0, and a garbled render scores near 1.
///
/// - Parameters:
///   - transcript: The text that a speech recognizer heard in the render.
///   - sentence: The text that was rendered.
/// - Returns: The number of characters that must be inserted, deleted or replaced to turn the transcript into the
///   sentence, divided by the sentence's length. It can be greater than 1. A sentence without letters or digits
///   returns 0.
public func transcriptError(_ transcript: String, _ sentence: String) -> Double {
  let heard = Array(transcript.lowercased().filter { $0.isLetter || $0.isNumber })
  let said = Array(sentence.lowercased().filter { $0.isLetter || $0.isNumber })
  guard !said.isEmpty else { return 0 }
  // The Levenshtein distance, computed one row at a time.
  var row = Array(0...said.count)
  for (i, h) in heard.enumerated() {
    var next = [i + 1]
    for (j, s) in said.enumerated() {
      next.append(min(row[j + 1] + 1, next[j] + 1, row[j] + (h == s ? 0 : 1)))
    }
    row = next
  }
  return Double(row[said.count]) / Double(said.count)
}
