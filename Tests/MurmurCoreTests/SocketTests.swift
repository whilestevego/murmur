import Darwin
import XCTest
@testable import MurmurCore

final class SocketTests: XCTestCase {
  var dir: URL!
  var path: String { dir.appendingPathComponent("t.sock").path }

  override func setUpWithError() throws {
    dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: dir)
  }

  func testARequestArrivesWhole() throws {
    let server = try XCTUnwrap(listenSocket(path))
    defer { close(server) }
    let client = try XCTUnwrap(connectSocket(path))
    let request = Data(#"{"stop":{}}"#.utf8)
    writeAll(client, request)
    close(client)
    let conn = accept(server, nil, nil)
    defer { close(conn) }
    XCTAssertEqual(readAll(conn), request)
  }

  func testOnlyThisUserCanConnect() throws {
    let server = try XCTUnwrap(listenSocket(path))
    defer { close(server) }
    let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
    XCTAssertEqual(mode, 0o700)
  }

  func testReplacesAStaleSocketFile() throws {
    try Data("left over".utf8).write(to: URL(fileURLWithPath: path))
    let server = try XCTUnwrap(listenSocket(path))
    close(server)
  }

  func testNothingListening() {
    XCTAssertNil(connectSocket(path))
  }

  /// A connected pair, without a path.
  func pair() -> (Int32, Int32) {
    var fds: [Int32] = [0, 0]
    XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds), 0)
    var on: Int32 = 1
    setsockopt(fds[1], SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    return (fds[0], fds[1])
  }

  func testReadStopsAtItsLimit() {
    let (reader, writer) = pair()
    let sent = 256 * 1024
    let done = expectation(description: "writer gave up")
    Thread.detachNewThread {
      writeAll(writer, Data(count: sent))  // blocks until the reader closes
      close(writer)
      done.fulfill()
    }
    let got = readAll(reader, limit: 100_000).count
    close(reader)
    XCTAssertGreaterThanOrEqual(got, 100_000)
    XCTAssertLessThan(got, sent)
    wait(for: [done], timeout: 5)
  }

  /// murmurd sets a receive timeout: a client that never closes gets what it sent so far.
  func testReadReturnsWhatArrivedOnTimeout() {
    let (reader, writer) = pair()
    defer { close(reader); close(writer) }
    var timeout = timeval(tv_sec: 0, tv_usec: 200_000)
    setsockopt(reader, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    writeAll(writer, Data(#"{"sto"#.utf8))
    XCTAssertEqual(readAll(reader), Data(#"{"sto"#.utf8))
  }
}
