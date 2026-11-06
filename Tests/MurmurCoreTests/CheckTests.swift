import XCTest

@testable import MurmurCore

final class CheckTests: XCTestCase {
  // The transcripts are what Parakeet heard in real renders.
  let sentence =
    "The reply expands on the plan's post-MVP items, known gaps, and open questions, several of which need your decisions."

  func testAGoodRenderPasses() {
    let heard =
      "The reply expands on the plans post-MVP items, known gaps, and open questions, several of which need your decisions."
    XCTAssertEqual(transcriptError(heard, sentence), 0)
  }

  func testAGarbledRenderFails() {
    let heard =
      "Oh that's terri inari story here is already still ready andari inari stowering here is already still ready."
    XCTAssertGreaterThan(transcriptError(heard, sentence), Defaults.garbled)
  }

  func testRespellingsAndNumbersPass() {
    XCTAssertEqual(transcriptError("Use MCP.", "Use M C P."), 0)
    XCTAssertEqual(transcriptError("BrL 13158 needs 2,700 lines.", "BRL 13158 needs 2700 lines."), 0)
    XCTAssertLessThan(
      transcriptError("Still working five minutes in.", "Still working, 5 minutes in."), Defaults.garbled)
  }

  func testCountsEdits() {
    XCTAssertEqual(transcriptError("kitten", "sitting"), 3.0 / 7)
    XCTAssertEqual(transcriptError("", "abcd"), 1)
    XCTAssertEqual(transcriptError("abc", "..."), 0)
  }
}
