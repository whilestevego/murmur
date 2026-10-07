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
murmur voices                          # list them; ✓ marks the installed ones
murmur voices install af_nicole        # install some (~510 KB each)
murmur voices install --all            # or all of them (~14 MB)
murmur --voice bm_lewis "Hello."       # a missing voice also installs on first use
```

`af_heart` is the default and comes with the model. The other voice packs download from
[onnx-community/Kokoro-82M-v1.0-ONNX](https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX),
which publishes each voice as a separate file in the format the Neural Engine pipeline reads.

## Claude Code

`claude-plugin/` is a Claude Code plugin that gives Claude a voice. Load it with
`claude --plugin-dir claude-plugin`, or add the folder to `CLAUDE_CODE_PLUGIN_DIRS` in
`~/.claude/settings.json`.

| | What you hear |
|---|---|
| Turn summaries | when a long turn finishes, one line on what was done (written by Claude Haiku) |
| Needs you | "Claude needs your permission to use Bash", "Claude has a question for you." |
| Background tasks | "Background task: all 42 tests passed" |
| Progress check-ins | every few minutes of a long turn: "Still working, 10 minutes in. Writing the parser. 3 of 7 steps done." |
| Rate-limit warnings | once per usage window: "Heads up: you've used 90 percent of your five hour limit." |
| `/read` | Claude's last answer, with code blocks replaced by "Code omitted." |
| `/tldr-aloud` | a 2–3 sentence summary of the session so far |
| `/hush` | mutes this session, or unmutes it |

- **Quiet by default:** it only speaks when you're away from this session, meaning Ghostty
  isn't the front app or another tab is focused. In other terminals it can't tell, so it
  always speaks. `/read` and `/tldr-aloud` always speak.
- **Interrupt, don't stack:** each new line cuts off whatever is still playing.
- **A voice per session:** every running Claude session gets its own voice, kept for as
  long as the session runs.

Everything is configurable in `/config` under **murmur**: when to speak (`away` or
`always`), each feature on or off, the long-turn and check-in intervals, the rate-limit
threshold, speaking rate, the summary style (`haiku` or the free `first-sentence`), one
fixed voice for every session, or the list of voices sessions are given.

## Development

```sh
make test     # unit tests for the shared core
make build    # release build into .build/release
```

Logs: `~/Library/Caches/murmur/murmurd.log`.

## License

MIT for murmur. Kokoro-82M is Apache-2.0; FluidAudio is Apache-2.0.
