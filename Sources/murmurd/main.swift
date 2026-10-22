import AVFoundation
import Darwin
import FluidAudio
import Foundation
import MurmurCore
import ObjCTry

/// Writes a timestamped line to standard error, which is murmurd's log.
func log(_ message: String) {
  FileHandle.standardError.write(Data("\(Date()) \(message)\n".utf8))
}

/// Creates and loads the Kokoro model.
///
/// The model comes from the installed bundle if there is one. Otherwise, FluidAudio downloads it from Hugging Face into
/// its cache.
func makeKokoro() async throws -> KokoroAneManager {
  let m = KokoroAneManager(defaultVoice: Defaults.voice, directory: Paths.bundleInstalled ? Paths.models : nil)
  try await m.initialize()
  return m
}

/// Renders and plays speech requests, in the order they arrive.
actor Speaker {
  /// The model load, shared by every caller.
  private var loading: Task<KokoroAneManager, Error>?
  private let engine = AVAudioEngine()
  private let player = AVAudioPlayerNode()
  private let cache = PhraseCache()
  // swift-format-ignore: NeverForceUnwrap
  // AVAudioFormat returns nil only for an unsupported sample rate or channel count, and these are fixed.
  private let format = AVAudioFormat(standardFormatWithSampleRate: Defaults.sampleRate, channels: 1)!
  /// The current generation of requests.
  ///
  /// Stopping or interrupting increments it. A speaking loop from an older generation stops scheduling audio.
  private var generation = 0
  /// The task that speaks the latest request.
  ///
  /// A queued request waits for it, and an interrupting request doesn't.
  private var tail: Task<Void, Never>?
  /// The latest render, which the next render waits for.
  private var rendering: Task<[Float], Error>?
  /// The number of buffers scheduled on the player that haven't finished playing.
  private var pending = 0
  /// The number of requests that are speaking or waiting to speak.
  ///
  /// The engine keeps running while there are any.
  private var speaking = 0
  /// The time of the latest request or finished buffer.
  private var lastActive = Date()
  /// The pronunciation dictionary, loaded on first use.
  private lazy var lexicon = Lexicon.load()
  /// The custom pronunciations last given to Kokoro.
  ///
  /// Setting them rebuilds Kokoro's text front end, so they're set only when they change.
  private var sounds: [String: String] = [:]

  init() {
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: format)
    // The engine stops itself when the output device changes, such as to headphones, AirPlay or a display's speakers.
    let center = NotificationCenter.default
    center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
      Task { await self?.outputChanged() }
    }
  }

  /// Handles a request.
  ///
  /// A stop request, or a speak request that interrupts, ends the current speech and discards queued speech. Any other
  /// speak request is queued behind the earlier ones.
  func handle(_ request: Request) {
    lastActive = Date()
    let speech: Speech? = if case .speak(let s) = request { s } else { nil }
    if speech?.interrupt ?? true {
      generation += 1
      // Stopping the player calls its scheduled buffers' completion handlers, which brings `pending` back to 0.
      player.stop()
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

  /// A Boolean value that indicates whether nothing is playing or queued, and no request has arrived for
  /// `Defaults.idleExit` seconds.
  var isIdle: Bool { pending == 0 && speaking == 0 && Date().timeIntervalSince(lastActive) > Defaults.idleExit }

  /// Returns the loaded model, and loads it on first use.
  ///
  /// Callers that arrive during the load wait for that load instead of starting another. If the load fails, the next
  /// call tries again.
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
      // Let the next call retry, unless another call has already started a new load.
      if loading == task { loading = nil }
      throw error
    }
  }

  /// Speaks a request, one sentence at a time.
  ///
  /// Each sentence plays while the next one renders. Speaking stops when a stop or interrupt starts a new generation.
  private func speak(_ request: Speech, _ gen: Int) async {
    var request = request
    if !VoicePacks.isInstalled(request.voice) {
      // Install a missing voice before the first sentence. The download is about 510 KB.
      log("installing voice \(request.voice)")
      do { try await VoicePacks.install(request.voice) } catch {
        log("voice \(request.voice): \(error); speaking with \(Defaults.voice)")
        request.voice = Defaults.voice
      }
    }
    for (sentence, sounds) in prepare(request.text, Pronunciations.load(from: request.pronunciationsFile), lexicon) {
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
      // A stop or interrupt may have arrived while the player was starting.
      guard gen == generation else { return }
      play(samples)
    }
  }

  /// Renders a sentence after any render already in progress.
  ///
  /// Rendering one sentence at a time keeps each sentence's custom pronunciations set while it renders, even when an
  /// interrupting request is rendering too.
  private func render(_ sentence: String, _ sounds: [String: String], voice: String, speed: Float) async throws
    -> [Float]
  {
    let previous = rendering
    let task = Task {
      // Wait for the previous render, whether or not it succeeded.
      _ = try? await previous?.value
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
  /// Right after the engine starts, its output may not be running yet. The player then raises "player did not see an IO
  /// cycle" instead of playing, so this waits briefly and tries again, up to three times.
  ///
  /// - Returns: `true` if the player is playing.
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

  /// Schedules samples on the player, which ``startPlayer()`` must already have started.
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

  /// Handles a change of audio output device.
  ///
  /// Audio scheduled on the old device is dropped. The next sentence starts the engine on the new device.
  private func outputChanged() {
    log("audio output changed")
    // Stopping the player calls its scheduled buffers' completion handlers.
    player.stop()
  }

  /// Records that a buffer finished playing.
  private func played() {
    pending = max(0, pending - 1)
    lastActive = Date()
    stopIfDone()
  }

  /// Stops the engine once nothing is left to play or render, which releases the audio device.
  ///
  /// The engine keeps running between the sentences of a request.
  private func stopIfDone() {
    if pending == 0 && speaking == 0 {
      player.stop()
      engine.stop()
    }
  }
}

// `murmurd --phonemes [--pronunciations FILE] TEXT…` prints how the text will be pronounced, then exits. It takes the
// same options as `murmur`.
if CommandLine.arguments.count > 2 && CommandLine.arguments[1] == "--phonemes" {
  let request: Speech
  do { request = try Speech(arguments: Array(CommandLine.arguments.dropFirst(2))) } catch {
    FileHandle.standardError.write(Data("murmurd: \(error)\n".utf8))
    exit(1)
  }
  do {
    let m = try await makeKokoro()
    for (sentence, sounds) in prepare(
      request.text, Pronunciations.load(from: request.pronunciationsFile), Lexicon.load())
    {
      await m.setEnglishCustomLexicon(sounds)
      print(try await m.phonemes(for: sentence))
    }
  } catch {
    FileHandle.standardError.write(Data("murmurd: \(error)\n".utf8))
  }
  exit(0)
}

try? FileManager.default.createDirectory(at: Paths.caches, withIntermediateDirectories: true)
// Only one murmurd runs per user. The process that holds the lock owns the socket, so only it may replace or remove the
// socket file. The lock is released when the process exits, however it exits.
let lock = open(Paths.caches.appendingPathComponent("murmurd.lock").path, O_RDWR | O_CREAT, 0o600)
guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else { exit(0) }
guard let server = listenSocket(Paths.socket.path) else {
  log("can't listen on \(Paths.socket.path)")
  exit(1)
}
log("listening on \(Paths.socket.path)")

let speaker = Speaker()
// A single reader hands requests to the speaker in the order they arrived. A task per request could reach the speaker
// in any order.
let (requests, arrived) = AsyncStream.makeStream(of: Request.self)
Task {
  for await request in requests { await speaker.handle(request) }
}

Thread.detachNewThread {
  while true {
    let client = accept(server, nil, nil)
    guard client >= 0 else { continue }
    // A client writes its request and closes the connection at once. The timeout keeps a client that never closes from
    // holding up the requests after it.
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

// Exit when idle, so that the model doesn't stay in memory. The next request starts murmurd again.
while true {
  try? await Task.sleep(for: .seconds(30))
  if await speaker.isIdle {
    log("idle, exiting")
    unlink(Paths.socket.path)
    exit(0)
  }
}
