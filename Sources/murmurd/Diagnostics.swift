import CoreML
import Darwin
import FluidAudio
import Foundation
import MurmurCore

/// The compute units that each stage of Kokoro runs on.
let kokoroUnits = KokoroAneComputeUnits.aneTailCpu

/// Everything known about one render of a sentence that was checked with Parakeet.
///
/// When a render is garbled, murmurd writes one report for each attempt at the sentence, including the attempt that
/// succeeded, so a garbled render can be compared with a good one.
struct RenderReport: Encodable {
  /// The time the report was made.
  let time = Date()
  /// The sentence's cache key.
  let key: String
  /// The attempt number, starting at 1.
  let attempt: Int
  /// The text of the whole request, before normalization.
  let request: String
  /// The normalized sentence that was rendered.
  let sentence: String
  /// The custom pronunciations that applied to the sentence, as phonemes by word.
  let sounds: [String: String]
  /// The name of the voice.
  let voice: String
  /// The speaking rate, where 1 is normal speed.
  let speed: Float
  /// The text that Parakeet heard.
  let transcript: String
  /// The ``transcriptError(_:_:)`` of the transcript.
  let transcriptError: Double
  /// A Boolean value that indicates whether the render counts as garbled.
  let garbled: Bool
  /// Measurements of the samples.
  let audio: AudioReport
  /// What Kokoro did, or `nil` if the report isn't available.
  let kokoro: KokoroReport?
  /// The state of the computer.
  let system = SystemReport()
}

/// Measurements of a render's samples.
struct AudioReport: Encodable {
  /// The length, in seconds.
  let seconds: Double
  /// The largest absolute sample.
  let peak: Float
  /// The root mean square of the samples.
  let rms: Float
  /// The share of adjacent samples that differ in sign.
  ///
  /// Garbled renders have measured about 0.06 to 0.09, and good renders about 0.1 to 0.17.
  let zeroCrossingRate: Double

  /// Creates the measurements of samples at ``Defaults/sampleRate``.
  ///
  /// - Parameter samples: The samples to measure.
  init(_ samples: [Float]) {
    seconds = Double(samples.count) / Defaults.sampleRate
    peak = samples.map(abs).max() ?? 0
    rms = samples.isEmpty ? 0 : (samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
    let crossings = zip(samples, samples.dropFirst()).filter { ($0 < 0) != ($1 < 0) }.count
    zeroCrossingRate = samples.count < 2 ? 0 : Double(crossings) / Double(samples.count - 1)
  }
}

/// What Kokoro did in a render, and its state at the time.
struct KokoroReport: Encodable {
  /// The text after FluidAudio's normalization, or `nil` if FluidAudio didn't report it.
  let normalizedText: String?
  /// The phonemes that Kokoro read.
  let phonemes: String
  /// The token IDs, including the start and end tokens.
  let inputIds: [Int32]
  /// The number of acoustic frames that Kokoro predicted for each token.
  let predictedDurations: [Int32]
  /// The number of tokens.
  let encoderTokens: Int
  /// The number of acoustic frames.
  let acousticFrames: Int
  /// A Boolean value that indicates whether every chunk used FluidAudio's fast vocoder.
  let usedFastVocoder: Bool
  /// The time each stage took, in milliseconds.
  let stageMilliseconds: [String: Double]
  /// The compute units that each stage runs on.
  let computeUnits: [String: String]
  /// The time since Kokoro loaded, in seconds.
  let secondsSinceLoad: Double
  /// The number of renders since Kokoro loaded, including this one.
  let rendersSinceLoad: Int
  /// The time from the end of the previous render to the start of this one, in seconds, or `nil` for the first render.
  let secondsSincePreviousRender: Double?

  /// Creates a report from FluidAudio's result.
  ///
  /// - Parameters:
  ///   - result: The result of the render.
  ///   - loaded: The time Kokoro loaded.
  ///   - renders: The number of renders since Kokoro loaded, including this one.
  ///   - idle: The time from the end of the previous render to the start of this one, in seconds.
  init(_ result: KokoroAneSynthesisResult, loaded: Date, renders: Int, idle: Double?) {
    normalizedText = result.normalizedText
    phonemes = result.phonemes
    inputIds = result.inputIds
    predictedDurations = result.predictedDurations
    encoderTokens = result.encoderTokens
    acousticFrames = result.acousticFrames
    usedFastVocoder = result.usedFastVocoder
    let t = result.timings
    stageMilliseconds = [
      "albert": t.albert, "postAlbert": t.postAlbert, "alignment": t.alignment, "prosody": t.prosody,
      "noise": t.noise, "vocoder": t.vocoder, "tail": t.tail, "nativeSource": t.nativeSource, "decoder": t.decoder,
      "generator": t.generator,
    ]
    let u = kokoroUnits
    computeUnits = [
      "albert": u.albert, "postAlbert": u.postAlbert, "alignment": u.alignment, "prosody": u.prosody,
      "noise": u.noise, "vocoder": u.vocoder, "tail": u.tail,
    ].mapValues(name)
    secondsSinceLoad = Date().timeIntervalSince(loaded)
    rendersSinceLoad = renders
    secondsSincePreviousRender = idle
  }
}

/// The state of the computer when a report is made.
struct SystemReport: Encodable {
  /// The macOS version and build.
  let os = ProcessInfo.processInfo.operatingSystemVersionString
  /// The hardware model, such as `Mac16,8`.
  let model = sysctlString("hw.model")
  /// The name of the processor, such as `Apple M4 Pro`.
  let chip = sysctlString("machdep.cpu.brand_string")
  /// The amount of physical memory, in bytes.
  let memoryBytes = ProcessInfo.processInfo.physicalMemory
  /// The memory that murmurd uses, in bytes, as Activity Monitor counts it.
  let footprintBytes = footprint()
  /// The thermal state, from `nominal` to `critical`.
  let thermalState = name(ProcessInfo.processInfo.thermalState)
  /// A Boolean value that indicates whether Low Power Mode is on.
  let lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
  /// The time since the computer started, in seconds.
  let systemUptimeSeconds = ProcessInfo.processInfo.systemUptime
  /// The time murmurd's executable was last modified, which is when it was installed.
  let murmurdModified =
    Bundle.main.executableURL.flatMap {
      try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date
    }
}

/// Writes every attempt at a garbled sentence to a new directory in ``Paths/garbled``.
///
/// The directory is named by the time and the cache key. Each attempt has its samples, in the phrase cache's format, in
/// `attempt-N.f32` and its report in `attempt-N.json`. Failures to write are logged.
///
/// - Parameter attempts: Every attempt at the sentence, in order.
func saveGarbled(_ attempts: [(samples: [Float], report: RenderReport)]) {
  guard let first = attempts.first?.report else { return }
  let stamp = ISO8601DateFormatter.string(
    from: first.time, timeZone: .current, formatOptions: [.withFullDate, .withTime])
  let dir = Paths.garbled.appendingPathComponent("\(stamp)-\(first.key)")
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  encoder.dateEncodingStrategy = .iso8601
  do {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for (samples, report) in attempts {
      let name = "attempt-\(report.attempt)"
      try samples.withUnsafeBytes { Data($0) }.write(to: dir.appendingPathComponent("\(name).f32"))
      try encoder.encode(report).write(to: dir.appendingPathComponent("\(name).json"))
    }
    log("saved the garbled renders of \(first.key) in \(dir.path)")
  } catch {
    log("couldn't save the garbled renders of \(first.key): \(error)")
  }
}

/// Returns the name of a set of compute units.
private func name(_ units: MLComputeUnits) -> String {
  switch units {
  case .cpuOnly: "cpuOnly"
  case .cpuAndGPU: "cpuAndGPU"
  case .cpuAndNeuralEngine: "cpuAndNeuralEngine"
  case .all: "all"
  @unknown default: "\(units.rawValue)"
  }
}

/// Returns the name of a thermal state.
private func name(_ state: ProcessInfo.ThermalState) -> String {
  switch state {
  case .nominal: "nominal"
  case .fair: "fair"
  case .serious: "serious"
  case .critical: "critical"
  @unknown default: "\(state.rawValue)"
  }
}

/// Returns a string value from `sysctl`, or `nil` if the name is unknown.
private func sysctlString(_ name: String) -> String? {
  var size = 0
  guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
  var bytes = [UInt8](repeating: 0, count: size)
  guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
  return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
}

/// Returns the memory that murmurd uses, in bytes, or `nil` if the system doesn't report it.
private func footprint() -> UInt64? {
  var usage = rusage_info_v4()
  let status = withUnsafeMutablePointer(to: &usage) {
    $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0) }
  }
  return status == 0 ? usage.ri_phys_footprint : nil
}
