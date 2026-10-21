import XCTest

@testable import MurmurCore

final class PhraseCacheTests: XCTestCase {
  var dir: URL!

  override func setUpWithError() throws {
    dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: dir)
  }

  /// Room for `n` phrases of 4 samples each.
  func cache(holding n: Int) -> PhraseCache { PhraseCache(directory: dir, limit: n * 4 * MemoryLayout<Float>.stride) }

  /// Modification times order the cache; keep each step distinct.
  func tick() { usleep(20_000) }

  func testSamplesComeBackExactly() {
    let c = cache(holding: 10)
    let samples: [Float] = [0.5, -1, .pi, -.leastNonzeroMagnitude]
    c.put("a", samples)
    XCTAssertEqual(c.get("a"), samples)
    XCTAssertNil(c.get("missing"))
  }

  func testAnEmptyFileIsAMiss() throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data().write(to: cache(holding: 10).url("empty"))
    XCTAssertNil(cache(holding: 10).get("empty"))
  }

  func testEvictsTheLeastRecentlyPlayed() {
    let c = cache(holding: 2)
    for key in ["a", "b"] {
      c.put(key, [1, 2, 3, 4])
      tick()
    }
    XCTAssertNotNil(c.get("a"))  // played: now b is the oldest
    tick()
    c.put("c", [1, 2, 3, 4])
    XCTAssertNotNil(c.get("a"))
    XCTAssertNil(c.get("b"))
    XCTAssertNotNil(c.get("c"))
  }
}
