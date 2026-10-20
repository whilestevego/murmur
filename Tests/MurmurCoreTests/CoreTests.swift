import XCTest
@testable import MurmurCore

final class CoreTests: XCTestCase {
  func testSentences() {
    XCTAssertEqual(sentences("Done. Tests pass! Ready?"), ["Done.", "Tests pass!", "Ready?"])
    XCTAssertEqual(sentences("v1.2 is out.\nNext line"), ["v1.2 is out.", "Next line"])
    XCTAssertEqual(sentences("  \n\n "), [])
    XCTAssertEqual(sentences("No end"), ["No end"])
  }

  func testCacheKeyIsStableAndDistinct() {
    let a = cacheKey("Hi.", voice: "af_heart", speed: 1)
    XCTAssertEqual(a, cacheKey("Hi.", voice: "af_heart", speed: 1))
    XCTAssertNotEqual(a, cacheKey("Hi.", voice: "bf_emma", speed: 1))
    XCTAssertNotEqual(a, cacheKey("Hi.", voice: "af_heart", speed: 1.2))
  }

  func testRequestRoundTrips() throws {
    let r = Request(text: "Hello", voice: "bm_george", speed: 1.1, interrupt: true)
    XCTAssertEqual(try JSONDecoder().decode(Request.self, from: JSONEncoder().encode(r)), r)
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

  func testParseFile() {
    let mine = Pronunciations.parse("# mine\nGIF = jif\n  SQL=S Q L \nbroken line\n= nothing\n")
    XCTAssertEqual(mine, ["GIF": "jif", "SQL": "S Q L"])
  }

  func testDefaultsFixTheKnownCases() {
    XCTAssertEqual(pronounce("Check the ID in the JSON.", Pronunciations.defaults), "Check the I D in the Jason.")
    XCTAssertEqual(pronounce("Todo: update the todos and the to-do list.", Pronunciations.defaults), "To do: update the to dos and the to do list.")
    XCTAssertEqual(pronounce("Run /goto, then GOTO.", Pronunciations.defaults), "Run /go to, then go to.")
    XCTAssertEqual(pronounce("Both repos, one monorepo.", Pronunciations.defaults), "Both reepos, one mono reepo.")
  }
}

final class NormalizeTests: XCTestCase {
  // The rest is scored against NeMo's cases: make nemo.
  static let techCases: [(String, String)] = [
    ("It’s “done”.", "It's \"done\"."),
    ("See https://github.com/whilestevego/murmur.", "See github dot com."),
    ("Edit ~/src/app/main.swift now", "Edit main dot swift now"),
    ("say/hooks/register.tsx", "register dot T S X"),
    ("and/or client/server", "and or client slash server"),
    ("plugin.json, process.env and e.g. this", "plugin dot jason, process dot env and e.g. this"),
    ("v1.2.3, 0.15.5 and v2", "version 1 point 2 point 3, 0 point 15 point 5 and version 2"),
    ("on 2026-10-19, July 4 or 17 may 2010", "on October 19th 20 26, July 4th or the 17th of May 20 10"),
    ("we may 5 times", "we may 5 times"),
    ("1,000 users, 2048 tokens, in 1994", "1000 users, 2048 tokens, in 19 94"),
    ("$5, $1, $5.50, $0.05, $2M, $20/mo", "5 dollars, 1 dollar, 5 dollars 50 cents, 5 cents, 2 million dollars, 20 dollars per month"),
    ("50% at 10:30, 3:05, 9:00 or 1:49 p.m.", "50 percent at 10 30, 3 oh 5, 9 o'clock or 1 49 PM"),
    ("pages 10-20, -3", "pages 10 to 20, minus 3"),
    ("200ms, 1 MB, 5s, 2x, 12kg/kg, 2°C", "200 milliseconds, 1 megabyte, 5 seconds, 2 x, 12 kilograms per kilogram, 2 degrees Celsius"),
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

  func testTechText() {
    for (input, spoken) in Self.techCases { XCTAssertEqual(normalize(input), spoken, input) }
  }

  func testNamesSplitOnlyWhenUnknown() {
    XCTAssertEqual(normalize("setVoiceName HTTPServer PRs"), "set Voice Name HTTP Server PRs")
    XCTAssertEqual(normalize("macOS iPhone") { ["macOS", "iPhone"].contains($0) }, "macOS iPhone")
  }

  func testNumberWords() {
    XCTAssertEqual(ordinalWords(32), "thirty second")
    XCTAssertEqual(ordinalWords(2007), "two thousand seventh")
    XCTAssertEqual(ordinalWords(12), "twelfth")
    XCTAssertEqual([1, 2, 3, 4, 11, 12, 13, 21, 22, 111].map(ordinalSuffix), ["st", "nd", "rd", "th", "th", "th", "th", "st", "nd", "th"])
    XCTAssertEqual([roman("IV"), roman("XL"), roman("MIX"), roman("II")], [4, 40, nil, 2])
  }
}

final class LexiconTests: XCTestCase {
  let lexicon = Lexicon(
    lower: ["today": "tədˈA", "base": "bˈAs", "fix": "fˈɪks", "stop": "stˈɑp", "wait": "wˈAt", "add": "ˈæd", "built": "bˈɪlt", "in": "ˈɪn", "apis": "ˈApɪs"],
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
    XCTAssertNil(s["today"])  // known words are left to Kokoro
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
}
