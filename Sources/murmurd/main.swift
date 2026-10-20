import AVFoundation
import Darwin
import FluidAudio
import Foundation
import MurmurCore

func log(_ message: String) {
  FileHandle.standardError.write(Data("\(Date()) \(message)\n".utf8))
}

/// Phrase cache: one raw Float32 file per rendered sentence, least recently played evicted first.
enum PhraseCache {
  static func url(_ key: String) -> URL { Paths.phrases.appendingPathComponent("\(key).f32") }

  static func get(_ key: String) -> [Float]? {
    guard let data = try? Data(contentsOf: url(key)), !data.isEmpty else { return nil }
    try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url(key).path)
    return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
  }

  static func put(_ key: String, _ samples: [Float]) {
    let fm = FileManager.default
    try? fm.createDirectory(at: Paths.phrases, withIntermediateDirectories: true)
    try? samples.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: url(key), options: .atomic)
    let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
    guard let files = try? fm.contentsOfDirectory(at: Paths.phrases, includingPropertiesForKeys: Array(keys)) else { return }
    let entries = files.compactMap { f -> (URL, Date, Int)? in
      guard let v = try? f.resourceValues(forKeys: keys) else { return nil }
      return (f, v.contentModificationDate ?? .distantPast, v.fileSize ?? 0)
    }.sorted { $0.1 > $1.1 }
    var total = 0
    for (file, _, size) in entries {
      total += size
      if total > Defaults.cacheBytes { try? fm.removeItem(at: file) }
    }
  }
}

actor Speaker {
  private var loading: Task<KokoroAneManager, Error>?
  private let engine = AVAudioEngine()
  private let player = AVAudioPlayerNode()
  private let format = AVAudioFormat(standardFormatWithSampleRate: Defaults.sampleRate, channels: 1)!
  /// Bumped by stop/interrupt: a speaking loop from an older generation stops scheduling.
  private var generation = 0
  /// The latest request's loop; a queued request waits for it, an interrupting one doesn't.
  private var tail: Task<Void, Never>?
  private var pending = 0
  private var lastActive = Date()
  private lazy var lexicon = Lexicon.load()
  /// The exact sounds last handed to Kokoro; setting them rebuilds its text frontend, so only on a change.
  private var sounds: [String: String] = [:]

  init() {
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: format)
  }

  func handle(_ request: Request) {
    lastActive = Date()
    if request.stop || request.interrupt {
      generation += 1
      player.stop()  // fires the scheduled buffers' completions, so `pending` drains
    }
    if request.stop { return }
    let gen = generation
    let previous = request.interrupt ? nil : tail
    tail = Task {
      await previous?.value
      await self.speak(request, gen)
    }
  }

  var isIdle: Bool { pending == 0 && Date().timeIntervalSince(lastActive) > Defaults.idleExit }

  /// Every caller awaits the same load, so a request arriving mid-load doesn't start a second one.
  private func loadedManager() async throws -> KokoroAneManager {
    let task = loading ?? Task {
      let bundled = FileManager.default.fileExists(atPath: Paths.models.appendingPathComponent("kokoro-82m-coreml/ANE/vocab.json").path)
      log("loading Kokoro (\(bundled ? Paths.models.path : "download from HuggingFace"))")
      let m = KokoroAneManager(defaultVoice: Defaults.voice, directory: bundled ? Paths.models : nil)
      try await m.initialize()
      log("Kokoro ready")
      return m
    }
    loading = task
    do {
      return try await task.value
    } catch {
      if loading == task { loading = nil }  // the next request retries, unless one already has
      throw error
    }
  }

  /// Renders sentence by sentence: the first plays while the next renders.
  private func speak(_ request: Request, _ gen: Int) async {
    var request = request
    if !VoicePacks.isInstalled(request.voice) {
      // On-the-fly install: the first sentence waits for one ~510 KB download, later ones don't.
      log("installing voice \(request.voice)")
      do { try await VoicePacks.install(request.voice) } catch {
        log("voice \(request.voice): \(error); speaking with \(Defaults.voice)")
        request.voice = Defaults.voice
      }
    }
    for (sentence, sounds) in prepare(request.text, Pronunciations.load(), lexicon) {
      guard gen == generation else { return }
      let key = cacheKey(sentence + soundsKey(sounds), voice: request.voice, speed: request.speed)
      var samples = PhraseCache.get(key)
      if samples == nil {
        do {
          let manager = try await loadedManager()
          if sounds != self.sounds {
            await manager.setEnglishCustomLexicon(sounds)
            self.sounds = sounds
          }
          let out = try await manager.synthesizeDetailed(text: sentence, voice: request.voice, speed: request.speed)
          samples = out.samples
          PhraseCache.put(key, out.samples)
        } catch {
          log("synthesis failed: \(error)")
          return
        }
      }
      guard gen == generation, let samples, !samples.isEmpty else { return }
      play(samples)
    }
  }

  private func play(_ samples: [Float]) {
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
    buffer.frameLength = buffer.frameCapacity
    samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
    if !engine.isRunning {
      do { try engine.start() } catch { return log("audio engine failed: \(error)") }
    }
    pending += 1
    player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
      Task { await self.played() }
    }
    if !player.isPlaying { player.play() }
  }

  /// Releases the audio device as soon as nothing is left to play.
  private func played() {
    pending = max(0, pending - 1)
    lastActive = Date()
    if pending == 0 {
      player.stop()
      engine.stop()
    }
  }
}

// `murmurd --phonemes TEXT…`: print how the text will be pronounced, then exit (behind `murmur phonemes`).
if CommandLine.arguments.count > 2 && CommandLine.arguments[1] == "--phonemes" {
  let text = CommandLine.arguments.dropFirst(2).joined(separator: " ")
  let bundled = FileManager.default.fileExists(atPath: Paths.models.appendingPathComponent("kokoro-82m-coreml/ANE/vocab.json").path)
  let done = DispatchSemaphore(value: 0)
  Task {
    do {
      let m = KokoroAneManager(defaultVoice: Defaults.voice, directory: bundled ? Paths.models : nil)
      try await m.initialize()
      for (sentence, sounds) in prepare(text, Pronunciations.load(), Lexicon.load()) {
        await m.setEnglishCustomLexicon(sounds)
        print(try await m.phonemes(for: sentence))
      }
    } catch {
      FileHandle.standardError.write(Data("murmurd: \(error)\n".utf8))
    }
    done.signal()
  }
  done.wait()
  exit(0)
}

// One murmurd per user: if another is already listening, leave it be.
if let fd = connectSocket(Paths.socket.path) {
  close(fd)
  exit(0)
}
try? FileManager.default.createDirectory(at: Paths.caches, withIntermediateDirectories: true)
guard let server = listenSocket(Paths.socket.path) else {
  log("can't listen on \(Paths.socket.path)")
  exit(1)
}
log("listening on \(Paths.socket.path)")

let speaker = Speaker()

Thread.detachNewThread {
  while true {
    let client = accept(server, nil, nil)
    guard client >= 0 else { continue }
    let data = readAll(client)
    close(client)
    guard let request = try? JSONDecoder().decode(Request.self, from: data) else {
      log("ignored a malformed request")
      continue
    }
    Task { await speaker.handle(request) }
  }
}

// Exit when idle: no model in memory, no audio device held. The next `murmur` restarts it.
Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
  Task {
    if await speaker.isIdle {
      log("idle, exiting")
      unlink(Paths.socket.path)
      exit(0)
    }
  }
}
RunLoop.main.run()
