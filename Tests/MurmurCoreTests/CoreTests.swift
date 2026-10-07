import XCTest
@testable import MurmurCore

final class CoreTests: XCTestCase {
  func testSentences() {
    XCTAssertEqual(sentences("Done. Tests pass! Ready?"), ["Done.", "Tests pass!", "Ready?"])
    XCTAssertEqual(sentences("v1.2 is out.\nNext line"), ["v1.2 is out.", "Next line"])
    XCTAssertEqual(sentences("  \n\n "), [])
    XCTAssertEqual(sentences("No end"), ["No end"])
  }

  func testCacheKeyIsStableAndDistinct() {
    let a = cacheKey("Hi.", voice: "af_heart", speed: 1)
    XCTAssertEqual(a, cacheKey("Hi.", voice: "af_heart", speed: 1))
    XCTAssertNotEqual(a, cacheKey("Hi.", voice: "bf_emma", speed: 1))
    XCTAssertNotEqual(a, cacheKey("Hi.", voice: "af_heart", speed: 1.2))
  }

  func testRequestRoundTrips() throws {
    let r = Request(text: "Hello", voice: "bm_george", speed: 1.1, interrupt: true)
    XCTAssertEqual(try JSONDecoder().decode(Request.self, from: JSONEncoder().encode(r)), r)
  }

  func testSocketPathFitsSunPath() {
    XCTAssertLessThan(Paths.socket.path.utf8.count, 104)
  }
}

final class VoiceTests: XCTestCase {
  func testCatalog() {
    XCTAssertEqual(voiceCatalog.count, 28)
    XCTAssertEqual(Set(voiceCatalog.map(\.name)).count, 28)
    XCTAssertTrue(voiceCatalog.contains(VoiceInfo(name: "af_nicole", group: "American female")))
    XCTAssertTrue(voiceCatalog.contains { $0.name == Defaults.voice })
    XCTAssertEqual(VoiceInfo(name: "bm_george", group: "British male").label, "George")
  }

  func testInstallRejectsUnknownVoiceWithoutNetwork() async {
    do {
      try await VoicePacks.install("xx_nobody")
      XCTFail("expected an error")
    } catch {
      XCTAssertEqual("\(error)", "unknown voice xx_nobody (see: murmur voices)")
    }
  }
}
