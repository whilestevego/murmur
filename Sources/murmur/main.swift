import Darwin
import Foundation
import MurmurCore

/// ANSI styling, only when the stream is a terminal and NO_COLOR is unset (no-color.org).
struct Style {
  let on: Bool
  init(fd: Int32) { on = isatty(fd) == 1 && getenv("NO_COLOR") == nil }
  private func wrap(_ code: String, _ s: String) -> String { on ? "\u{1B}[\(code)m\(s)\u{1B}[0m" : s }
  func bold(_ s: String) -> String { wrap("1", s) }
  func dim(_ s: String) -> String { wrap("2", s) }
  func accent(_ s: String) -> String { wrap("36", s) }  // cyan: commands and flags
  func arg(_ s: String) -> String { wrap("33", s) }  // yellow: placeholders
  func head(_ s: String) -> String { wrap("1;35", s) }  // bold magenta: section titles
  func error(_ s: String) -> String { wrap("1;31", s) }
}

func usage(_ st: Style) -> String {
  // Pads by visible width: the escape codes take no columns.
  func row(_ left: String, _ text: String) -> String {
    let visible = left.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression).count
    return "  " + left + String(repeating: " ", count: max(2, 31 - visible)) + text
  }
  return ([
    "\(st.bold("murmur")) \(st.dim("·")) speak text with Kokoro on the Apple Neural Engine",
    "",
    st.head("USAGE"),
    row(st.accent("murmur") + " " + st.arg("[options] <text…>"), "speak text, or pipe it on stdin; returns at once"),
    row(st.accent("murmur stop"), "stop speaking and drop anything queued"),
    row(st.accent("murmur voices"), "list the 28 voices with Kokoro's grades; ✓ marks the installed ones"),
    row(st.accent("murmur voices install") + " " + st.arg("NAME…"), "install voices " + st.dim("(or --all; a missing voice also installs on first use)")),
    row(st.accent("murmur phonemes") + " " + st.arg("<text…>"), "show how text will be pronounced"),
    row(st.accent("murmur setup") + " " + st.arg("[--from DIR]"), "install the voice model"),
    "",
    st.head("OPTIONS"),
    row(st.accent("-v, --voice") + " " + st.arg("NAME"), "voice to speak with " + st.dim("(default af_heart)")),
    row(st.accent("-s, --speed") + " " + st.arg("X"), "speaking rate " + st.dim("(default 1.0)")),
    row(st.accent("-i, --interrupt"), "cut off what's playing instead of queueing"),
    row(st.accent("--"), "end of options: the rest is text, even if it starts with -"),
    row(st.accent("-h, --help"), "show this help"),
    "",
    st.head("EXAMPLES"),
    "  " + st.dim("$") + " murmur \"The build is green.\"",
    "  " + st.dim("$") + " git log -1 --format=%s | murmur --voice bm_george",
    "  " + st.dim("$") + " murmur voices install af_nicole bm_lewis",
    "",
    st.dim("Logs: \(Paths.log.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))"),
  ]).joined(separator: "\n")
}

func fail(_ message: String) -> Never {
  let st = Style(fd: 2)
  FileHandle.standardError.write(Data("\(st.error("murmur:")) \(message)\n".utf8))
  exit(1)
}

/// murmurd sits next to this binary (both come from the same build or install).
func daemonPath() -> String {
  // The executable's real path: argv[0] is just "murmur" when it was found through $PATH.
  let me = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
  return me.deletingLastPathComponent().appendingPathComponent("murmurd").path
}

/// Starts murmurd in its own session, detached from this terminal, logging to Paths.log.
func spawnDaemon() {
  try? FileManager.default.createDirectory(at: Paths.caches, withIntermediateDirectories: true)
  var actions: posix_spawn_file_actions_t?
  posix_spawn_file_actions_init(&actions)
  posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
  posix_spawn_file_actions_addopen(&actions, 1, Paths.log.path, O_WRONLY | O_CREAT | O_APPEND, 0o600)
  posix_spawn_file_actions_adddup2(&actions, 1, 2)
  var attrs: posix_spawnattr_t?
  posix_spawnattr_init(&attrs)
  posix_spawnattr_setflags(&attrs, Int16(POSIX_SPAWN_SETSID))
  let path = daemonPath()
  var pid: pid_t = 0
  let argv: [UnsafeMutablePointer<CChar>?] = [strdup(path), nil]
  let status = posix_spawn(&pid, path, &actions, &attrs, argv, environ)
  if status != 0 { fail("couldn't start \(path): \(String(cString: strerror(status)))") }
}

func send(_ request: Request) {
  var fd = connectSocket(Paths.socket.path)
  if fd == nil {
    spawnDaemon()
    for _ in 0..<60 where fd == nil {  // murmurd listens before it loads the model: this is quick
      usleep(50_000)
      fd = connectSocket(Paths.socket.path)
    }
  }
  guard let fd else { fail("murmurd didn't start; see \(Paths.log.path)") }
  writeAll(fd, try! JSONEncoder().encode(request))
  close(fd)
}

func setup(from dir: String?) {
  let fm = FileManager.default
  guard let dir else {
    let st = Style(fd: 1)
    print("\(st.accent("→")) No \(st.accent("--from")) given: the model \(st.dim("(~110 MB)")) downloads from HuggingFace on first use.")
    return
  }
  let source = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath)
  guard fm.fileExists(atPath: source.appendingPathComponent("kokoro-82m-coreml/ANE/vocab.json").path) else {
    fail("\(source.path) isn't a KokoroBundle (no kokoro-82m-coreml/ANE/vocab.json)")
  }
  // APFS clones: effectively free, and the source stays untouched.
  for (from, to) in [(source, Paths.models), (source.appendingPathComponent("kokoro"), Paths.g2p)] {
    try? fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? fm.removeItem(at: to)
    do { try fm.copyItem(at: from, to: to) } catch { fail("copying to \(to.path): \(error)") }
  }
  let st = Style(fd: 1)
  print("\(st.accent("✓")) Installed the voice model to \(st.bold(Paths.models.path))")
}

func listVoices() {
  let st = Style(fd: 1)
  var group = ""
  for v in voiceCatalog {
    if v.group != group {
      group = v.group
      print((group == voiceCatalog[0].group ? "" : "\n") + st.head(group.uppercased()))
    }
    let installed = VoicePacks.isInstalled(v.name)
    let mark = installed ? st.accent("✓") : st.dim("·")
    let name = v.name.padding(toLength: 13, withPad: " ", startingAt: 0)
    let label = v.label.padding(toLength: 9, withPad: " ", startingAt: 0)
    print("  \(mark) \(installed ? st.bold(name) : st.dim(name)) \(st.dim(label)) \(v.grade)"
      + (v.name == Defaults.voice ? String(repeating: " ", count: 4 - v.grade.count) + st.arg("default") : ""))
  }
  let missing = voiceCatalog.filter { !VoicePacks.isInstalled($0.name) }.count
  print("\n" + st.dim("\(voiceCatalog.count - missing) installed, \(missing) not. ")
    + (missing > 0 ? st.dim("Install with ") + st.accent("murmur voices install NAME…") + st.dim(" or ") + st.accent("--all") + st.dim(", or just use one.") : ""))
}

func installVoices(_ names: [String]) async {
  let st = Style(fd: 1)
  let wanted = names == ["--all"] ? voiceCatalog.map(\.name) : names
  guard !wanted.isEmpty else { fail("name the voices to install, or --all (see: murmur voices)") }
  if let unknown = wanted.first(where: { name in !voiceCatalog.contains { $0.name == name } }) {
    fail("unknown voice \(unknown) (see: murmur voices)")
  }
  let todo = wanted.filter { !VoicePacks.isInstalled($0) }
  if todo.isEmpty { return print("\(st.accent("✓")) already installed") }
  var failed = false
  for name in todo {
    do {
      try await VoicePacks.install(name)
      print("\(st.accent("✓")) \(name)")
    } catch {
      failed = true
      FileHandle.standardError.write(Data("\(Style(fd: 2).error("✗")) \(name): \(error)\n".utf8))
    }
  }
  if failed { exit(1) }
}

var args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "-h", "--help":
  print(usage(Style(fd: 1)))
case "stop":
  send(Request(stop: true))
case "phonemes":
  // The phonemizer lives with the model in murmurd; run it once there.
  let words = Array(args.dropFirst())
  guard !words.isEmpty else { fail("phonemes needs text") }
  let argv: [UnsafeMutablePointer<CChar>?] = ([daemonPath(), "--phonemes"] + words).map { strdup($0) } + [nil]
  execv(daemonPath(), argv)
  fail("couldn't run \(daemonPath())")
case "voices":
  if args.count > 1 && args[1] == "install" { await installVoices(Array(args.dropFirst(2))) } else { listVoices() }
case "setup":
  let i = args.firstIndex(of: "--from")
  setup(from: i.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil })
default:
  var request = Request()
  var words: [String] = []
  while !args.isEmpty {
    let arg = args.removeFirst()
    switch arg {
    case "-v", "--voice":
      guard !args.isEmpty else { fail("--voice needs a name") }
      request.voice = args.removeFirst()
      guard voiceCatalog.contains(where: { $0.name == request.voice }) else {
        fail("unknown voice \(request.voice) (see: murmur voices)")
      }
    case "-s", "--speed":
      guard let s = args.isEmpty ? nil : Float(args.removeFirst()), s > 0 else { fail("--speed needs a number") }
      request.speed = s
    case "-i", "--interrupt": request.interrupt = true
    case "--":  // everything after is text, even if it looks like a flag
      words += args
      args = []
    default: words.append(arg)
    }
  }
  request.text = words.isEmpty && isatty(0) == 0
    ? String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
    : words.joined(separator: " ")
  guard !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
    FileHandle.standardError.write(Data((usage(Style(fd: 2)) + "\n").utf8))
    exit(2)
  }
  send(request)
}
