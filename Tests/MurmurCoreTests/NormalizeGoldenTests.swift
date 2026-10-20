import XCTest
@testable import MurmurCore

/// While normalize is restructured, its output on every known input must not change by a single character.
/// MURMUR_RECORD_GOLDEN=1 swift test records it again.
final class NormalizeGoldenTests: XCTestCase {
  let nemo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("nemo")

  func testOutputIsUnchanged() throws {
    let files = try FileManager.default.contentsOfDirectory(atPath: nemo.path).filter { $0.hasSuffix(".txt") }.sorted()
    var inputs = NormalizeTests.techCases.flatMap { [$0.0, $0.1] }
    for name in files where name != "deviations.txt" {
      for line in try String(contentsOf: nemo.appendingPathComponent(name), encoding: .utf8).split(separator: "\n") {
        inputs += line.split(separator: "~", maxSplits: 1).map(String.init)
      }
    }
    let lines = inputs.map { "\($0.debugDescription) → \(normalize($0).debugDescription)" }
    let golden = nemo.appendingPathComponent("normalize.golden")
    if ProcessInfo.processInfo.environment["MURMUR_RECORD_GOLDEN"] != nil {
      try (lines.joined(separator: "\n") + "\n").write(to: golden, atomically: true, encoding: .utf8)
    }
    let recorded = try String(contentsOf: golden, encoding: .utf8).split(separator: "\n").map(String.init)
    XCTAssertEqual(lines.count, recorded.count)
    for (got, want) in zip(lines, recorded) where got != want { XCTFail("\(got)\n  was \(want)") }
  }
}
