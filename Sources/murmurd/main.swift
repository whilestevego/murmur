import AVFoundation
import Darwin
import FluidAudio
import Foundation
import MurmurCore
import ObjCTry

func log(_ message: String) {
  FileHandle.standardError.write(Data("\(Date()) \(message)\n".utf8))
}

/// Kokoro from the installed bundle, else downloaded from HuggingFace into FluidAudio's cache.
func makeKokoro() async throws -> KokoroAneManager {
  let m = KokoroAneManager(defaultVoice: Defaults.voice, directory: Paths.bundleInstalled ? Paths.models : nil)
  try await m.initialize()
  return m
}

actor Speaker {
  private var loading: Task<KokoroAneManager, Error>?
  private let engine = AVAudioEngine()
  private let player = AVAudioPlayerNode()
  private let cache = PhraseCache()
  // swift-format-ignore: NeverForceUnwrap
  // Only nil for a channel count or sample rate AVAudioFormat can't take, and these are fixed.
  private let format = AVAudioFormat(standardFormatWithSampleRate: Defaults.sampleRate, channels: 1)!
  /// Bumped by stop/interrupt: a speaking loop from an older generation stops scheduling.
  private var generation = 0
  /// The latest request's loop; a queued request waits for it, an interrupting one doesn't.
  private var tail: Task<Void, Never>?
  /// The latest render; the next one waits for it.
  private var rendering: Task<[Float], Error>?
  private var pending = 0
  /// Requests speaking or queued to: while any are, the engine stays running.
  private var speaking = 0
  private var lastActive = Date()
  private lazy var lexicon = Lexicon.load()
  /// The exact sounds last handed to Kokoro; setting them rebuilds its text frontend, so only on a change.
  private var sounds: [String: String] = [:]

  init() {
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: format)
    // The engine stops itself when the output device changes (headphones, AirPlay, a display's speakers).
    let center = NotificationCenter.default
    center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
      Task { await self?.outputChanged() }
    }
  }

  func handle(_ request: Request) {
    lastActive = Date()
    let speech: Speech? = if case .speak(let s) = request { s } else { nil }
    if speech?.interrupt ?? true {
      generation += 1
      player.stop()  // fires the scheduled buffers' completions, so `pending` drains
    }
    guard let speech else { return }
    let gen = generation
    let previous = speech.interrupt ? nil : tail
    speaking += 1
    tail = Task {
      await previous?.value
      await self.speak(speech, gen)
      self.speaking -= 1
      self.stopIfDone()
    }
  }

  var isIdle: Bool { pending == 0 && speaking == 0 && Date().timeIntervalSince(lastActive) > Defaults.idleExit }

  /// Every caller awaits the same load, so a request arriving mid-load doesn't start a second one.
  private func loadedManager() async throws -> KokoroAneManager {
    let task =
      loading
      ?? Task {
        log("loading Kokoro (\(Paths.bundleInstalled ? Paths.models.path : "download from HuggingFace"))")
        let m = try await makeKokoro()
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
  private func speak(_ request: Speech, _ gen: Int) async {
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
      var samples = cache.get(key)
      if samples == nil {
        do {
          let out = try await render(sentence, sounds, voice: request.voice, speed: request.speed)
          samples = out
          cache.put(key, out)
        } catch {
          log("synthesis failed: \(error)")
          return
        }
      }
      guard gen == generation, let samples, !samples.isEmpty else { return }
      guard await startPlayer() else { return }
      guard gen == generation else { return }  // a stop or interrupt may have come in while it started
      play(samples)
    }
  }

  /// One render at a time, each after the last: the sounds set for a sentence are still set when it renders, even if
  /// an interrupting request's loop is rendering too.
  private func render(_ sentence: String, _ sounds: [String: String], voice: String, speed: Float) async throws
    -> [Float]
  {
    let previous = rendering
    let task = Task {
      _ = try? await previous?.value  // a failed render doesn't hold up the next
      let manager = try await self.loadedManager()
      if sounds != self.sounds {
        await manager.setEnglishCustomLexicon(sounds)
        self.sounds = sounds
      }
      return try await manager.synthesizeDetailed(text: sentence, voice: voice, speed: speed).samples
    }
    rendering = task
    return try await task.value
  }

  /// Starts the engine and the player.
  ///
  /// Right after the engine starts, its output may not be running yet, and the player then raises "player did not see
  /// an IO cycle" instead of playing: so it waits a moment and tries again.
  private func startPlayer() async -> Bool {
    for attempt in 1...3 {
      if engine.isRunning && player.isPlaying { return true }
      if !engine.isRunning {
        do { try engine.start() } catch {
          log("audio engine failed: \(error)")
          return false
        }
      }
      guard let exception = objcTry({ player.play() }) else { return true }
      log("player didn't start (attempt \(attempt) of 3): \(exception.reason ?? exception.name.rawValue)")
      player.stop()
      engine.stop()
      try? await Task.sleep(for: .milliseconds(250 * attempt))
    }
    return false
  }

  /// Queues samples on the running player (see `startPlayer`).
  private func play(_ samples: [Float]) {
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
      let channel = buffer.floatChannelData?[0]
    else { return }
    buffer.frameLength = buffer.frameCapacity
    channel.update(from: samples, count: samples.count)
    pending += 1
    player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
      Task { await self.played() }
    }
  }

  /// Drops what was playing on the old output, so `pending` drains; the next sentence starts the engine on the new one.
  private func outputChanged() {
    log("audio output changed")
    player.stop()  // fires the scheduled buffers' completions
  }

  private func played() {
    pending = max(0, pending - 1)
    lastActive = Date()
    stopIfDone()
  }

  /// Releases the audio device once nothing is left to play or to render; between sentences the engine stays up.
  private func stopIfDone() {
    if pending == 0 && speaking == 0 {
      player.stop()
      engine.stop()
    }
  }
}

// `murmurd --phonemes TEXT…`: print how the text will be pronounced, then exit (behind `murmur phonemes`).
if CommandLine.arguments.count > 2 && CommandLine.arguments[1] == "--phonemes" {
  let text = CommandLine.arguments.dropFirst(2).joined(separator: " ")
  do {
    let m = try await makeKokoro()
    for (sentence, sounds) in prepare(text, Pronunciations.load(), Lexicon.load()) {
      await m.setEnglishCustomLexicon(sounds)
      print(try await m.phonemes(for: sentence))
    }
  } catch {
    FileHandle.standardError.write(Data("murmurd: \(error)\n".utf8))
  }
  exit(0)
}

try? FileManager.default.createDirectory(at: Paths.caches, withIntermediateDirectories: true)
// One murmurd per user: whoever holds the lock owns the socket, so only it may replace or remove it. The lock is
// released when the process exits, however it exits.
let lock = open(Paths.caches.appendingPathComponent("murmurd.lock").path, O_RDWR | O_CREAT, 0o600)
guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else { exit(0) }
guard let server = listenSocket(Paths.socket.path) else {
  log("can't listen on \(Paths.socket.path)")
  exit(1)
}
log("listening on \(Paths.socket.path)")

let speaker = Speaker()
// One reader hands requests to the speaker in the order they arrived; a task per request could reach it in any order.
let (requests, arrived) = AsyncStream.makeStream(of: Request.self)
Task {
  for await request in requests { await speaker.handle(request) }
}

Thread.detachNewThread {
  while true {
    let client = accept(server, nil, nil)
    guard client >= 0 else { continue }
    // murmur writes and closes at once; one that never closes mustn't hold up everyone after it.
    var timeout = timeval(tv_sec: 1, tv_usec: 0)
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    let data = readAll(client)
    close(client)
    guard let request = try? JSONDecoder().decode(Request.self, from: data) else {
      log("ignored a malformed request")
      continue
    }
    arrived.yield(request)
  }
}

// Exit when idle: no model in memory, no audio device held. The next `murmur` restarts it.
while true {
  try? await Task.sleep(for: .seconds(30))
  if await speaker.isIdle {
    log("idle, exiting")
    unlink(Paths.socket.path)
    exit(0)
  }
}
