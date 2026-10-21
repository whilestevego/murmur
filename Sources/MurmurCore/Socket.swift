import Darwin
import Foundation

private func address(_ path: String) -> sockaddr_un {
  var addr = sockaddr_un()
  addr.sun_family = sa_family_t(AF_UNIX)
  withUnsafeMutableBytes(of: &addr.sun_path) { buf in
    for (i, byte) in path.utf8.prefix(buf.count - 1).enumerated() { buf[i] = byte }
  }
  return addr
}

/// A connected socket to murmurd, or nil when nothing is listening.
public func connectSocket(_ path: String) -> Int32? {
  let fd = socket(AF_UNIX, SOCK_STREAM, 0)
  guard fd >= 0 else { return nil }
  var addr = address(path)
  let ok = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
    }
  }
  if !ok { close(fd) }
  return ok ? fd : nil
}

/// Binds and listens on `path`, replacing a stale socket file.
///
/// Returns nil if it can't.
public func listenSocket(_ path: String) -> Int32? {
  unlink(path)
  let fd = socket(AF_UNIX, SOCK_STREAM, 0)
  guard fd >= 0 else { return nil }
  var addr = address(path)
  let mask = umask(0o077)  // only this user can make murmurd speak, from the moment the socket exists
  let bound = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
    }
  }
  umask(mask)
  guard bound, listen(fd, 16) == 0 else {
    close(fd)
    return nil
  }
  return fd
}

/// Writes all of `data`, retrying short and interrupted writes; stops quietly if the other end goes away.
public func writeAll(_ fd: Int32, _ data: Data) {
  data.withUnsafeBytes { buf in
    guard let base = buf.baseAddress else { return }  // empty
    var offset = 0
    while offset < buf.count {
      let n = write(fd, base + offset, buf.count - offset)
      if n < 0 && errno == EINTR { continue }
      if n <= 0 { return }
      offset += n
    }
  }
}

/// Reads until the other end closes, `limit` bytes arrive, or the socket's receive timeout fires.
public func readAll(_ fd: Int32, limit: Int = 1 << 20) -> Data {
  var data = Data()
  var chunk = [UInt8](repeating: 0, count: 64 * 1024)
  while data.count < limit {
    let n = read(fd, &chunk, chunk.count)
    if n < 0 && errno == EINTR { continue }
    if n <= 0 { break }
    data.append(chunk, count: n)
  }
  return data
}
