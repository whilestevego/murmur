import ObjCTry
import XCTest

@testable import MurmurCore

final class CoreTests: XCTestCase {
  func testSentences() {
    XCTAssertEqual(sentences("Done. Tests pass! Ready?"), ["Done.", "Tests pass!", "Ready?"])
    XCTAssertEqual(sentences("v1.2 is out.\nNext line"), ["v1.2 is out.", "Next line"])
    XCTAssertEqual(sentences("  \n\n "), [])
    XCTAssertEqual(sentences("No end"), ["No end"])
    XCTAssertEqual(sentences("Pi is 3.14 today. Wait... what?"), ["Pi is 3.14 today.", "Wait...", "what?"])
  }

  func testAbbreviationsDontEndASentence() {
    XCTAssertEqual(sentences("Use e.g. this, i.e. that one."), ["Use e.g. this, i.e. that one."])
    XCTAssertEqual(sentences("Ask Dr. Smith (vs. Mr. Jones). Done."), ["Ask Dr. Smith (vs. Mr. Jones).", "Done."])
    XCTAssertEqual(sentences("A list (e.g. this) goes on."), ["A list (e.g. this) goes on."])
  }

  func testCacheKeyIsStableAndDistinct() {
    let a = cacheKey("Hi.", engine: .kokoro, voice: "af_heart", speed: 1)
    XCTAssertEqual(a, cacheKey("Hi.", engine: .kokoro, voice: "af_heart", speed: 1))
    XCTAssertNotEqual(a, cacheKey("Hi.", engine: .kokoro, voice: "bf_emma", speed: 1))
    XCTAssertNotEqual(a, cacheKey("Hi.", engine: .kokoro, voice: "af_heart", speed: 1.2))
  }

  func testSoundsKeyIsSortedAndChangesWithTheSounds() {
    XCTAssertEqual(soundsKey(["b": "2", "a": "1"]), "|a=1|b=2")
    XCTAssertEqual(soundsKey([:]), "")
    XCTAssertNotEqual(soundsKey(["rebase": "ɹˈibˌAs"]), soundsKey(["rebase": "ɹibˈAs"]))
  }

  func testRequestRoundTrips() throws {
    let speech = Speech(
      text: "Hello", engine: .kokoro, voice: "bm_george", speed: 1.1, interrupt: true, pronunciations: "/tmp/p")
    for r in [Request.speak(speech), .speak(Speech(text: "Hi")), .stop] {
      XCTAssertEqual(try JSONDecoder().decode(Request.self, from: JSONEncoder().encode(r)), r)
    }
  }

  /// Tests that a request without a pronunciations path still decodes, as one from an older client would.
  func testARequestWithoutPronunciationsDecodes() throws {
    let json = #"{"speak":{"_0":{"text":"Hi","voice":"af_heart","speed":1,"interrupt":false}}}"#
    XCTAssertEqual(try JSONDecoder().decode(Request.self, from: Data(json.utf8)), .speak(Speech(text: "Hi")))
  }

  func testObjCTryCatchesRaisedExceptions() {
    XCTAssertEqual(
      objcTry { NSException(name: .genericException, reason: "no IO cycle").raise() }?.reason, "no IO cycle")
    XCTAssertNil(objcTry {})
  }

  func testSocketPathFitsSunPath() {
    XCTAssertLessThan(Paths.socket.path.utf8.count, 104)
  }
}

final class VoiceTests: XCTestCase {
  func testCatalog() {
    XCTAssertEqual(voiceCatalog.count, 28)
    XCTAssertEqual(Set(voiceCatalog.map(\.name)).count, 28)
    XCTAssertTrue(voiceCatalog.contains(VoiceInfo(name: "af_nicole", group: "American female", grade: "B-")))
    XCTAssertEqual(voiceCatalog.first { $0.name == Defaults.voice }?.grade, "A")
    XCTAssertTrue(voiceCatalog.allSatisfy { $0.grade.range(of: "^[A-F][+-]?$", options: .regularExpression) != nil })
    XCTAssertTrue(voiceCatalog.contains { $0.name == Defaults.voice })
    XCTAssertEqual(VoiceInfo(name: "bm_george", group: "British male", grade: "C").label, "George")
  }

  func testInstallRejectsUnknownVoiceWithoutNetwork() async {
    do {
      try await VoicePacks.install("xx_nobody")
      XCTFail("expected an error")
    } catch {
      XCTAssertEqual("\(error)", "unknown voice xx_nobody (see: murmur voices)")
    }
  }
}

final class PronunciationTests: XCTestCase {
  func testWholeWordsOnlyAndCaseSensitive() {
    let d = ["ID": "I D", "IDs": "I Ds", "JSON": "Jason"]
    XCTAssertEqual(pronounce("Copy the session ID.", d), "Copy the session I D.")
    XCTAssertEqual(pronounce("The IDs match; parse the JSON.", d), "The I Ds match; parse the Jason.")
    XCTAssertEqual(pronounce("an id, an IDEA, a GUID, ID_1", d), "an id, an IDEA, a GUID, ID_1")
    XCTAssertEqual(pronounce("(ID)", d), "(I D)")
  }

  /// The pronunciation file that the tests use in place of the user's own.
  let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
    "../Fixtures/pronunciations")

  func testLoadPutsTheFileOverTheDefaults() {
    let loaded = Pronunciations.load(from: fixture)
    XCTAssertEqual(loaded["npm"], "node package manager")
    XCTAssertEqual(loaded["GIF"], "jif")
    XCTAssertEqual(loaded["JSON"], "Jason")
  }

  func testAMissingFileAddsNothing() {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    XCTAssertEqual(Pronunciations.load(from: missing), Pronunciations.defaults)
  }

  func testTheRequestChoosesTheFile() {
    XCTAssertEqual(Speech(pronunciations: fixture.path).pronunciationsFile, URL(fileURLWithPath: fixture.path))
    XCTAssertEqual(Speech().pronunciationsFile, Pronunciations.file)
  }

  func testParseFile() {
    let mine = Pronunciations.parse("# mine\nGIF = jif\n  SQL=S Q L \nbroken line\n= nothing\n")
    XCTAssertEqual(mine, ["GIF": "jif", "SQL": "S Q L"])
  }

  func testDefaultsFixTheKnownCases() {
    XCTAssertEqual(pronounce("Check the ID in the JSON.", Pronunciations.defaults), "Check the I D in the Jason.")
    XCTAssertEqual(
      pronounce("Todo: update the todos and the to-do list.", Pronunciations.defaults),
      "To do: update the to dos and the to do list.")
    XCTAssertEqual(pronounce("Run /goto, then GOTO.", Pronunciations.defaults), "Run /go to, then go to.")
    XCTAssertEqual(pronounce("Both repos, one monorepo.", Pronunciations.defaults), "Both reepos, one mono reepo.")
  }

  // These tests cover prepare, which runs normalization, respellings, sentence splitting and misaki's rules in turn.
  func testRespelledNamesArentSplitFirst() {
    let said = prepare("Check macOS, GraphQL and TodoWrite.", Pronunciations.defaults, Lexicon()).map(\.text)
    XCTAssertEqual(said, ["Check mac O S, graph Q L and to do write."])
  }

  func testSoundEntriesBecomeSoundsNotText() {
    let out = prepare("Open GitHub. Rebase it.", ["GitHub": "/ɡˈɪthʌb/", "rebase": "/ɹˈibˌAs/"], Lexicon())
    // GitHub has an exact pronunciation, so it isn't split into "Git Hub".
    XCTAssertEqual(out.map(\.text), ["Open GitHub.", "Rebase it."])
    // Each sentence gets the phonemes for its own words only.
    XCTAssertEqual(out.map(\.sounds), [["GitHub": "ɡˈɪthʌb"], ["Rebase": "ɹˈibˌAs"]])
  }
}

final class NormalizeTests: XCTestCase {
  // `make nemo` scores the remaining rules against NeMo's test cases.
  func testTechText() {
    let cases: [(String, String)] = [
      ("It’s “done”.", "It's \"done\"."),
      ("See https://github.com/whilestevego/murmur.", "See github dot com."),
      ("Edit ~/src/app/main.swift now", "Edit main dot swift now"),
      ("say/hooks/register.tsx", "register dot T S X"),
      ("and/or client/server", "and or client slash server"),
      ("plugin.json, process.env and e.g. this", "plugin dot jason, process dot env and e.g. this"),
      ("v1.2.3, 0.15.5 and v2", "version 1 point 2 point 3, 0 point 15 point 5 and version 2"),
      ("on 2026-10-19, July 4 or 17 may 2010", "on October 19th 20 26, July 4th or the 17th of May 20 10"),
      ("we may 5 times", "we may 5 times"),
      ("1,000 users, 2048 tokens, in 1994", "one thousand users, two thousand forty eight tokens, in 19 94"),
      (
        "$5, $1, $5.50, $0.05, $2M, $20/mo",
        "5 dollars, 1 dollar, 5 dollars 50 cents, 5 cents, 2 million dollars, 20 dollars per month"
      ),
      ("50% at 10:30, 3:05, 9:00 or 1:49 p.m.", "50 percent at 10 30, 3 oh 5, 9 o'clock or 1 49 PM"),
      ("pages 10-20, -3", "pages 10 to 20, minus 3"),
      (
        "200ms, 1 MB, 5s, 2x, 12kg/kg, 2°C",
        "200 milliseconds, 1 megabyte, 5 seconds, 2 x, 12 kilograms per kilogram, 2 degrees Celsius"
      ),
      ("H264 on x86, the 21st, ab9453", "H 264 on x 86, the 21st, ab 9 4 5 3"),
      ("1/2, 2 1/2, 3/4, 24/7", "1 half, 2 and a half, 3 quarters, 24 7"),
      ("the 1980s and '90s", "the 19 eighties and nineties"),
      ("call +1 (123) 123-5678 or 123.123.0.40", "call plus 1, 1 2 3, 1 2 3, 5 6 7 8 or 1 2 3 dot 1 2 3 dot 0 dot 4 0"),
      ("a.bc@gmail.com", "a dot bc at gmail dot com"),
      ("1-2=5", "1 minus 2 equals 5"),
      ("Chapter IV", "Chapter 4"),
      ("a → b, n >= 3, x & y, ~5, PR #45", "a to b, n at least 3, x and y, about 5, PR number 45"),
      ("user_id", "user id"),
      ("one line\n-3 next", "one line\nminus 3 next"),
    ]
    for (input, spoken) in cases { XCTAssertEqual(normalize(input), spoken, input) }
  }

  func testNamesSplitOnlyWhenUnknown() {
    XCTAssertEqual(normalize("setVoiceName HTTPServer PRs"), "set Voice Name HTTP Server PRs")
    XCTAssertEqual(normalize("macOS iPhone") { ["macOS", "iPhone"].contains($0) }, "macOS iPhone")
  }

  func testNumberWords() {
    XCTAssertEqual(ordinalWords(32), "thirty second")
    XCTAssertEqual(ordinalWords(2007), "two thousand seventh")
    XCTAssertEqual(ordinalWords(12), "twelfth")
    XCTAssertEqual(
      [1, 2, 3, 4, 11, 12, 13, 21, 22, 111].map(ordinalSuffix),
      ["st", "nd", "rd", "th", "th", "th", "th", "st", "nd", "th"])
    XCTAssertEqual([roman("IV"), roman("XL"), roman("MIX"), roman("II")], [4, 40, nil, 2])
  }

  func testCodeRulesNeMoDoesntCover() {
    let cases: [(String, String)] = [
      ("open file:///Users/me/src/app/main.swift", "open main dot swift"),
      ("C++ and x++", "C plus plus and x plus plus"),
      ("i.e. this", "i.e. this"),
      ("a t2000, not ab9453", "a t two thousand, not ab 9 4 5 3"),
    ]
    for (input, spoken) in cases { XCTAssertEqual(normalize(input), spoken, input) }
  }

  /// Tests that normalization keeps the line breaks in every NeMo case.
  ///
  /// Sentences end at line breaks, so no rule may remove or add one.
  func testLineBreaksSurvive() throws {
    let nemo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../nemo")
    let files = try FileManager.default.contentsOfDirectory(at: nemo, includingPropertiesForKeys: nil).filter {
      $0.pathExtension == "txt"
    }
    let written = try files.flatMap {
      try String(contentsOf: $0, encoding: .utf8).split(separator: "\n").compactMap { $0.split(separator: "~").first }
    }
    XCTAssertGreaterThan(written.count, 400)
    for w in written {
      XCTAssertEqual(
        normalize("one\n\(w)\ntwo").split(separator: "\n", omittingEmptySubsequences: false).count, 3, String(w))
    }
  }
}

final class LexiconTests: XCTestCase {
  let lexicon = Lexicon(
    lower: [
      "today": "tədˈA", "base": "bˈAs", "fix": "fˈɪks", "stop": "stˈɑp", "wait": "wˈAt", "add": "ˈæd", "built": "bˈɪlt",
      "in": "ˈɪn", "apis": "ˈApɪs",
    ],
    cased: ["P": "pˈi", "R": "ˈɑɹ", "A": "ˈA", "I": "ˈI"])

  func testMisakiEndings() {
    let s = lexicon.sounds(for: "today's fixes, bases, stopped, waited, added, stopping, waiting")
    XCTAssertEqual(s["today's"], "tədˈAz")
    XCTAssertEqual(s["fixes"], "fˈɪksᵻz")
    XCTAssertEqual(s["bases"], "bˈAsᵻz")
    XCTAssertEqual(s["stopped"], "stˈɑpt")
    XCTAssertEqual(s["waited"], "wˈAɾᵻd")
    XCTAssertEqual(s["added"], "ˈædᵻd")
    XCTAssertEqual(s["stopping"], "stˈɑpɪŋ")
    XCTAssertEqual(s["waiting"], "wˈAɾɪŋ")
  }

  func testInitialismsCompoundsAndYours() {
    let s = lexicon.sounds(for: "PRs, the PR's APIs built-in", mine: ["rebase": "ɹˈibˌAs"])
    XCTAssertEqual(s["PRs"], "pˈi ˈɑɹz")
    XCTAssertEqual(s["PR's"], "pˈi ˈɑɹz")
    XCTAssertEqual(s["APIs"], "ˈA pˈi ˈIz")
    XCTAssertEqual(s["built-in"], "bˈɪlt ˈɪn")
    // Words in the dictionary are left to Kokoro.
    XCTAssertNil(s["today"])
    let mine = lexicon.sounds(for: "Rebase, then rebased and rebasing", mine: ["rebase": "ɹˈibˌAs"])
    XCTAssertEqual(mine["Rebase"], "ɹˈibˌAs")
    XCTAssertEqual(mine["rebased"], "ɹˈibˌAst")
    XCTAssertEqual(mine["rebasing"], "ɹˈibˌAsɪŋ")
  }

  func testSoundsInThePronunciationFile() {
    let (respell, sounds) = Pronunciations.split(["JSON": "Jason", "rebase": "/ɹˈibˌAs/", "odd": "/"])
    XCTAssertEqual(respell, ["JSON": "Jason", "odd": "/"])
    XCTAssertEqual(sounds, ["rebase": "ɹˈibˌAs"])
  }

  func testMoreOfMisakisRules() {
    let lexicon = Lexicon(lower: ["story": "stˈɔɹi", "built": "bˈɪlt"], cased: ["A": "ˈA", "P": "pˈi", "I": "ˈI"])
    let s = lexicon.sounds(for: "stories, API, built-zzz")
    XCTAssertEqual(s["stories"], "stˈɔɹiz")
    // FluidAudio spells out initialisms by itself.
    XCTAssertNil(s["API"])
    // A compound with a part the rules can't work out is left to FluidAudio.
    XCTAssertNil(s["built-zzz"])
  }

  func testEntryIgnoresCase() {
    XCTAssertEqual(lexicon.entry("Today"), "tədˈA")
    XCTAssertEqual(lexicon.entry("TODAY"), "tədˈA")
    XCTAssertEqual(lexicon.entry("P"), "pˈi")
    XCTAssertNil(lexicon.entry("p"))
  }

  /// Tests that FluidAudio's dictionary still loads.
  ///
  /// If FluidAudio changed the format of its cache, the lexicon would be empty, and misaki's rules would stop working
  /// without an error.
  func testLoadsFluidAudiosList() throws {
    let lists = [Paths.models.appendingPathComponent("kokoro"), Paths.g2p].map {
      $0.appendingPathComponent("us_lexicon_cache.json")
    }
    try XCTSkipUnless(lists.contains { FileManager.default.fileExists(atPath: $0.path) }, "the model isn't installed")
    let loaded = Lexicon.load()
    XCTAssertGreaterThan(loaded.lower.count, 10_000)
    XCTAssertNotNil(loaded.entry("today"))
  }
}

final class ArgumentTests: XCTestCase {
  func speech(_ args: String...) throws -> Speech { try Speech(arguments: args) }

  func usageError(_ args: String...) -> String? {
    do {
      _ = try Speech(arguments: args)
      return nil
    } catch {
      return error.description
    }
  }

  func testOptionsAndText() throws {
    XCTAssertEqual(try speech("Hello", "there"), Speech(text: "Hello there"))
    XCTAssertEqual(
      try speech("-v", "bm_george", "Hi", "--speed", "1.5", "-i"),
      Speech(text: "Hi", voice: "bm_george", speed: 1.5, interrupt: true))
    XCTAssertEqual(
      try speech("--voice", "bf_emma", "-s", "0.8", "--interrupt"),
      Speech(voice: "bf_emma", speed: 0.8, interrupt: true))
    XCTAssertEqual(try speech(), Speech())
  }

  func testEngineOption() throws {
    XCTAssertEqual(try speech("-e", "kokoro", "Hi"), Speech(text: "Hi", engine: .kokoro))
    XCTAssertEqual(try speech("--engine", "kokoro").engine, .kokoro)
    XCTAssertEqual(usageError("--engine"), "--engine needs a name")
    XCTAssertEqual(usageError("-e", "nope"), "unknown engine nope (choose from: kokoro, chatterbox-nano)")
    XCTAssertEqual(try speech("-e", "chatterbox-nano", "Hi").engine, .chatterboxNano)
    XCTAssertEqual(try speech("-e", "cb-nano", "Hi").engine, .chatterboxNano)
  }

  func testStyleOption() throws {
    XCTAssertEqual(try speech("--style", "happy", "-e", "chatterbox-nano").style, "happy")
    XCTAssertEqual(usageError("--style"), "--style needs a name")
    XCTAssertEqual(usageError("--style", "laugh", "-e", "chatterbox-nano")?.hasPrefix("unknown style laugh"), true)
    XCTAssertEqual(usageError("--style", "happy", "Hi"), "--style needs --engine chatterbox-nano")
  }

  func testChatterboxNanoTakesNoVoiceOrSpeed() {
    XCTAssertEqual(
      usageError("-e", "chatterbox-nano", "-v", "af_heart"), "chatterbox-nano has one voice, so it doesn't take --voice"
    )
    XCTAssertEqual(usageError("--speed", "1.2", "-e", "chatterbox-nano"), "chatterbox-nano doesn't support --speed")
    // An option after "--" is text.
    XCTAssertNil(usageError("-e", "chatterbox-nano", "--", "-s", "is", "short"))
  }

  func testEverythingAfterDoubleDashIsText() throws {
    XCTAssertEqual(try speech("-i", "--", "-v", "is", "a", "flag"), Speech(text: "-v is a flag", interrupt: true))
  }

  func testPronunciationsOption() throws {
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
      "../Fixtures/pronunciations")
    let speech = try speech("--pronunciations", fixture.path, "Hi")
    XCTAssertEqual(speech.pronunciations, fixture.standardizedFileURL.path)
    XCTAssertEqual(speech.text, "Hi")
    // A relative path is resolved against the current directory, because murmurd runs in another one.
    let cwd = FileManager.default.currentDirectoryPath
    try XCTSkipUnless(fixture.standardizedFileURL.path.hasPrefix(cwd + "/"), "the tests aren't running in the package")
    let relative = String(fixture.standardizedFileURL.path.dropFirst(cwd.count + 1))
    XCTAssertEqual(try self.speech("--pronunciations", relative).pronunciations, fixture.standardizedFileURL.path)
  }

  func testBadOptions() {
    XCTAssertEqual(usageError("-v"), "--voice needs a name")
    XCTAssertEqual(usageError("--voice", "xx_nobody", "Hi"), "unknown voice xx_nobody (see: murmur voices)")
    for speed in ["0", "-1", "fast", "inf", "1e40", "nan"] {
      XCTAssertEqual(usageError("-s", speed, "Hi"), "--speed needs a number", speed)
    }
    XCTAssertEqual(usageError("Hi", "--speed"), "--speed needs a number")
    XCTAssertEqual(usageError("--pronunciations"), "--pronunciations needs a file")
    XCTAssertEqual(usageError("--pronunciations", "/nonexistent/p", "Hi"), "no pronunciations file at /nonexistent/p")
  }
}

final class NormalizeSafetyTests: XCTestCase {
  /// Tests that normalization leaves digits other than 0 to 9 alone.
  ///
  /// In a regular expression, `\d` matches any Unicode digit, but `Int` reads only ASCII digits.
  func testOtherDigitsAreLeftAlone() {
    for text in ["٣:30", "١:00:00", "１:05", "the ٣0s", "٣Q22", "₩٣"] {
      XCTAssertFalse(normalize(text).isEmpty, text)
    }
  }
}

final class TagTests: XCTestCase {
  func testTagsAreRemovedForKokoro() {
    XCTAssertEqual(withoutTags("[happy] It shipped! [laugh] Finally [clear throat]."), " It shipped! Finally.")
    XCTAssertEqual(withoutTags("See [1] and array[0]."), "See [1] and array[0].")
  }

  func testTagsSurviveNormalization() {
    let said = prepare("[happy] It shipped! [clear throat] Done.", [:], Lexicon()).map(\.text)
    XCTAssertEqual(said, ["[happy] It shipped!", "[clear throat] Done."])
  }

  func testStyleAppliesToSentencesWithoutTheirOwn() {
    XCTAssertEqual(nanoSentence("Hi.", style: "happy"), "[happy] Hi.")
    XCTAssertEqual(nanoSentence("[angry] Hi.", style: "happy"), "[angry] Hi.")
    // A sound tag isn't a style, so the style still applies.
    XCTAssertEqual(nanoSentence("[laugh] Hi.", style: "happy"), "[happy] [laugh] Hi.")
    XCTAssertEqual(nanoSentence("Hi.", style: nil), "Hi.")
  }

  func testDecimalsAreWrittenOutForNano() {
    XCTAssertEqual(nanoSentence("Pi is 3.14.", style: nil), "Pi is 3 point 1 4.")
    XCTAssertEqual(nanoSentence("Use 1.2.3 or v2.0 at 10.", style: nil), "Use 1.2.3 or v2.0 at 10.")
  }

  func testHalvesSplitAtTheMiddleCommaAndKeepTheStyle() throws {
    let (a, b) = try XCTUnwrap(halves("[happy] One, two three, four five six seven."))
    XCTAssertEqual(a, "[happy] One, two three,")
    XCTAssertEqual(b, "[happy] four five six seven.")
    let (c, d) = try XCTUnwrap(halves("Say [clear throat] it."))
    XCTAssertEqual(c, "Say [clear throat]")
    XCTAssertEqual(d, "it.")
    XCTAssertNil(halves("[happy] Word."))
  }
}
