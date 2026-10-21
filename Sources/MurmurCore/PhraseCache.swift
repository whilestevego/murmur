import Foundation

/// Phrase cache: one raw Float32 file per rendered sentence, least recently played evicted first.
public struct PhraseCache: Sendable {
  public let directory: URL
  /// Total size kept, in bytes.
  public let limit: Int

  public init(directory: URL = Paths.phrases, limit: Int = Defaults.cacheBytes) {
    self.directory = directory
    self.limit = limit
  }

  func url(_ key: String) -> URL { directory.appendingPathComponent("\(key).f32") }

  public func get(_ key: String) -> [Float]? {
    guard let data = try? Data(contentsOf: url(key)), !data.isEmpty else { return nil }
    try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url(key).path)
    return [Float](unsafeUninitializedCapacity: data.count / MemoryLayout<Float>.stride) { buffer, count in
      count = data.copyBytes(to: buffer) / MemoryLayout<Float>.stride
    }
  }

  public func put(_ key: String, _ samples: [Float]) {
    let fm = FileManager.default
    try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
    try? samples.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: url(key), options: .atomic)
    let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
    guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)) else { return }
    let entries = files.compactMap { f -> (URL, Date, Int)? in
      guard let v = try? f.resourceValues(forKeys: keys) else { return nil }
      return (f, v.contentModificationDate ?? .distantPast, v.fileSize ?? 0)
    }.sorted { $0.1 > $1.1 }
    var total = 0
    for (file, _, size) in entries {
      total += size
      if total > limit { try? fm.removeItem(at: file) }
    }
  }
}
