import Foundation

/// murmur's settings.
///
/// The file has one setting on each line, in the form `name = value`, like the pronunciation file. Unknown names are
/// ignored.
public struct Settings: Equatable, Sendable {
  /// The file of settings.
  public static let file = Paths.home.appendingPathComponent(".config/murmur/config")

  /// A Boolean value that indicates whether murmurd checks each new Kokoro render with Parakeet.
  ///
  /// The setting is `check-renders = on`, and it's off by default. When it's on, murmurd loads Parakeet, and downloads
  /// it on first use, which is about 460 MB. A render that Parakeet can't hear is rendered again, and every attempt is
  /// saved with a report in ``Paths/garbled``.
  public var checkRenders = false

  /// Reads the settings from a file.
  ///
  /// The file is read on every call, so an edit applies to the next request. A missing file leaves every setting at
  /// its default.
  ///
  /// - Parameter file: The file of settings.
  /// - Returns: The settings.
  public static func load(from file: URL) -> Settings {
    let values = (try? String(contentsOf: file, encoding: .utf8)).map(Pronunciations.parse) ?? [:]
    var settings = Settings()
    if let value = values["check-renders"] {
      settings.checkRenders = ["on", "true", "yes", "1"].contains(value.lowercased())
    }
    return settings
  }
}
