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

/// Connects to a Unix domain socket.
///
/// - Parameter path: The socket's path.
/// - Returns: The connected file descriptor, or `nil` if nothing is listening.
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

/// Creates a Unix domain socket and listens on it.
///
/// Any file already at the path is removed first. Only the current user can connect to the socket.
///
/// - Parameter path: The socket's path.
/// - Returns: The listening file descriptor, or `nil` if the socket can't be created.
public func listenSocket(_ path: String) -> Int32? {
  unlink(path)
  let fd = socket(AF_UNIX, SOCK_STREAM, 0)
  guard fd >= 0 else { return nil }
  var addr = address(path)
  // Set the permissions as the socket is created, so that no other user can connect even briefly.
  let mask = umask(0o077)
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

/// Writes all of the data to a file descriptor.
///
/// Partial and interrupted writes are retried. Writing stops early, without an error, if the other end closes.
///
/// - Parameters:
///   - fd: The file descriptor to write to.
///   - data: The data to write.
public func writeAll(_ fd: Int32, _ data: Data) {
  data.withUnsafeBytes { buf in
    // An empty buffer has no base address.
    guard let base = buf.baseAddress else { return }
    var offset = 0
    while offset < buf.count {
      let n = write(fd, base + offset, buf.count - offset)
      if n < 0 && errno == EINTR { continue }
      if n <= 0 { return }
      offset += n
    }
  }
}

/// Reads from a file descriptor until the other end closes.
///
/// Reading also stops after at least `limit` bytes, or when the socket's receive timeout expires.
///
/// - Parameters:
///   - fd: The file descriptor to read from.
///   - limit: The number of bytes after which reading stops. The result can exceed it by up to one read.
/// - Returns: The data read.
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
