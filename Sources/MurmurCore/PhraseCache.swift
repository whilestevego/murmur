import Foundation

/// A disk cache of rendered sentences.
///
/// Each sentence is stored as a file of raw 32-bit float samples. When the cache grows past its limit, the least
/// recently used files are removed first.
public struct PhraseCache: Sendable {
  /// The directory that holds a `<key>.f32` file for each sentence.
  public let directory: URL
  /// The maximum total size of the cache, in bytes.
  public let limit: Int

  /// Creates a cache.
  ///
  /// - Parameters:
  ///   - directory: The directory to store the files in. It's created when the first sentence is cached.
  ///   - limit: The maximum total size of the cache, in bytes.
  public init(directory: URL = Paths.phrases, limit: Int = Defaults.cacheBytes) {
    self.directory = directory
    self.limit = limit
  }

  func url(_ key: String) -> URL { directory.appendingPathComponent("\(key).f32") }

  /// Returns the cached samples for a sentence.
  ///
  /// Reading an entry marks it as recently used, so it's evicted last.
  ///
  /// - Parameter key: The sentence's cache key, from ``cacheKey(_:voice:speed:)``.
  /// - Returns: The samples, or `nil` if the sentence isn't cached.
  public func get(_ key: String) -> [Float]? {
    guard let data = try? Data(contentsOf: url(key)), !data.isEmpty else { return nil }
    try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url(key).path)
    return [Float](unsafeUninitializedCapacity: data.count / MemoryLayout<Float>.stride) { buffer, count in
      count = data.copyBytes(to: buffer) / MemoryLayout<Float>.stride
    }
  }

  /// Caches the samples for a sentence.
  ///
  /// If the cache is then larger than ``limit``, the least recently used files are removed until it fits.
  ///
  /// - Parameters:
  ///   - key: The sentence's cache key, from ``cacheKey(_:voice:speed:)``.
  ///   - samples: The rendered samples.
  public func put(_ key: String, _ samples: [Float]) {
    let fm = FileManager.default
    try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
    try? samples.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: url(key), options: .atomic)
    let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
    guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)) else {
      return
    }
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
