# murmur

Fast, natural text-to-speech for the terminal on Apple Silicon. murmur speaks with
[Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) running on the **Apple Neural
Engine** through [FluidAudio](https://github.com/FluidInference/FluidAudio), so speaking
barely touches the CPU or battery.

```sh
murmur "The build is green."
git log -1 --format=%s | murmur          # or pipe text in
murmur --voice bf_emma --speed 1.1 "Cheerio."
murmur --interrupt "Stop that, say this."
murmur voices                           # all 28 voices, installed ones marked
murmur phonemes "Copy the ID."          # how it will be pronounced
murmur stop
```

`murmur` returns in a few milliseconds. The speaking happens in the background.

## How it works

- **`murmur`** is a tiny client (~140 KB). It sends the text to `murmurd` over a unix
  socket (`~/Library/Caches/murmur/murmurd.sock`, only accessible to you) and exits.
  If `murmurd` isn't running, it starts it.
- **`murmurd`** loads the model on its first request and keeps it loaded only while it's
  used. It **exits after 10 idle minutes**, so it uses no memory and doesn't hold the
  audio device while idle.
- **Sentence streaming**: the first sentence plays while the next one renders.
- **Phrase cache**: each rendered sentence is kept (32 MB, least recently played evicted
  first), so repeated phrases play without rendering again.
- Requests queue in order. `--interrupt` cuts in, `murmur stop` silences everything.

Measured on an M4 Pro: a fresh sentence renders in ~0.12 s once loaded; the client
returns in ~6 ms; the daemon idles at 0% CPU and ~420 MB while loaded. The first
start after install compiles the model for the Neural Engine (~7 s, once).

## Install

Requires Apple Silicon and macOS 14+.

```sh
git clone https://github.com/whilestevego/murmur && cd murmur
make install                 # builds and installs murmur + murmurd to ~/.local/bin
murmur setup                 # the model (~110 MB) downloads from HuggingFace on first use
murmur setup --from DIR      # or install it from a local KokoroBundle instead
```

`PREFIX=/usr/local make install` installs elsewhere. `make uninstall` removes both commands.

## Voices

All 28 of Kokoro's English voices: American and British, female and male.

```sh
murmur voices                          # list them with their grades; ✓ marks the installed ones
murmur voices install af_nicole        # install some (~510 KB each)
murmur voices install --all            # or all of them (~14 MB)
murmur --voice bm_lewis "Hello."       # a missing voice also installs on first use
```

`af_heart` is the default and comes with the model. The other voice packs download from
[onnx-community/Kokoro-82M-v1.0-ONNX](https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX),
which publishes each voice as a separate file in the format the Neural Engine pipeline reads.

The grade beside each voice is Kokoro's own, from its
[VOICES.md](https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md): an estimate of how good
and how plentiful the voice's training audio was. `af_heart` (A) and `af_bella` (A-) sound best;
the D and F voices are noticeably rougher.

## Chatterbox Nano

`--engine chatterbox-nano` speaks with Chatterbox Nano, from Resemble AI,
which sounds more natural than Kokoro and reads emotion and sound tags. It runs on the GPU,
renders about 3× faster than real time on an M4 Pro (Kokoro is about 30×), and needs macOS 15+.
Kokoro stays the default.

```sh
murmur setup --engine chatterbox-nano     # download it now (~711 MB), or let it download on first use
murmur -e chatterbox-nano "[happy] It shipped! [laugh] Finally."
murmur -e chatterbox-nano --style whispering "Every sentence is whispered."
```

- A tag applies to the sentence it's in. `--style` applies to every sentence that has no
  style tag of its own.
- Styles: `advertisement`, `angry`, `crying`, `dramatic`, `fear`, `happy`, `narration`,
  `sarcastic`, `surprised`, `whispering`.
- Sounds: `[chuckle]`, `[clear throat]`, `[cough]`, `[gasp]`, `[groan]`, `[laugh]`, `[shush]`,
  `[sigh]`, `[sniff]`.
- It has one voice and one speed, so it doesn't take `--voice` or `--speed`.
- Respellings apply, but pronunciations given as phonemes don't, and `murmur phonemes` is for
  Kokoro only.
- Kokoro removes the tags instead of reading them aloud.

## Pronunciation

Before Kokoro sees the text, murmur fixes what it would misread:

- **Numbers, dates and the like:** years (`1994` → "nineteen ninety four"), dates, times
  (`1:59 p.m.`, `10:30`), money (`$2.5 million`, `$20/mo`), percentages, fractions, measures
  (`12kg`, `2°C`, `200ms`), decades, ranges, phone numbers, IP addresses, emails, Roman
  numerals after words like Chapter, and simple math. These follow
  [NVIDIA NeMo's](https://github.com/NVIDIA/NeMo-text-processing) English text normalization:
  `make nemo` scores murmur against NeMo's 433 test cases. `Tests/nemo/exceptions.toml` gives
  murmur's own reading for the cases where it differs from NeMo on purpose, and lists the
  cases murmur doesn't read well yet, each group with its reason.
- **Code:** links (`https://github.com/a/b` → "github dot com"), file paths and names
  (`~/app/main.swift` → "main dot swift"), versions (`v1.2.3` → "version 1 point 2 point 3"),
  dotted names (`process.env`), `snake_case`, and `camelCase` names Kokoro doesn't know.
- **Word endings:** Kokoro's dictionary lists `today` but not `today's`, `rebased` or
  `PRs`. Its own text frontend, [misaki](https://github.com/hexgrad/misaki), works these out
  from the root word, but FluidAudio leaves them to a small neural guesser that misreads some.
  murmur applies misaki's rules first, so `today's` sounds like `today` plus "z".
- **A built-in list** of words Kokoro gets wrong: acronyms that are also dictionary words
  (`ID` is read as "id" otherwise) and tech words it spells out or mangles (`JSON`, `macOS`,
  `kubectl`, `stdout`…).

Add your own in `~/.config/murmur/pronunciations`, or in another file that you pass with
`--pronunciations FILE`, one per line. Each is either a
respelling or exact sounds between slashes, in the notation `murmur phonemes` prints. Exact
sounds also apply to the word's endings: `rebase` below fixes `rebased` and `rebasing` too.
Yours win over the built-in list and apply to the next thing said:

```
GIF = jif
Kubernetes = koo ber net eez
rebase = /ɹˈibˌAs/
```

Matching is by whole word. Respellings are case-sensitive, so `ID` changes while `id` and
`IDEA` don't. Check how anything will sound with `murmur phonemes "Copy the session ID."`.

## Development

```sh
make test     # unit tests for the shared core
make build    # release build into .build/release
make nemo     # score the text cleanup against NeMo's cases (needs the model; SHOW=1 lists failures)
make format   # format the Swift sources with swift-format (ships with Swift 6)
make lint     # fail on formatting or lint problems
```

CI runs the same lint, tests and NeMo scoring on every pull request. It scores the NeMo cases with a release build, and
runs the tests under the thread and address sanitizers. Compiler warnings count as errors.

Logs: `~/Library/Caches/murmur/murmurd.log`.

## License

MIT for murmur. Kokoro-82M is Apache-2.0; FluidAudio is Apache-2.0; the NeMo test cases in
`Tests/nemo` are Apache-2.0 (see its NOTICE).
