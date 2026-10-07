import type { EngineInterface, PluginOptions, Register } from 'claude-code'

import { checkinLine, firstSentence, prose, rateLimitLine, summaryPrompt, taskLine, voiceList } from './speech'
import type { Todo } from './speech'
import { claimVoice, parseTable } from './voices'

type Config = {
  speakWhen: string
  turnSummaries: boolean
  summaryStyle: string
  minTurnSeconds: number
  needsYou: boolean
  backgroundTasks: boolean
  checkins: boolean
  checkinMinutes: number
  rateLimitWarnings: boolean
  rateLimitPercent: number
  speed: number
  voice: string
  voices: string[]
}

function config(o: PluginOptions): Config {
  const num = (v: unknown, d: number) => (typeof v === 'number' && v > 0 ? v : d)
  return {
    speakWhen: o.speakWhen === 'always' ? 'always' : 'away',
    turnSummaries: o.turnSummaries !== false,
    summaryStyle: o.summaryStyle === 'first-sentence' ? 'first-sentence' : 'haiku',
    minTurnSeconds: num(o.minTurnSeconds, 20),
    needsYou: o.needsYou !== false,
    backgroundTasks: o.backgroundTasks !== false,
    checkins: o.checkins !== false,
    checkinMinutes: num(o.checkinMinutes, 5),
    rateLimitWarnings: o.rateLimitWarnings !== false,
    rateLimitPercent: num(o.rateLimitPercent, 90),
    speed: num(o.speed, 1),
    voice: typeof o.voice === 'string' ? o.voice.trim() : '',
    voices: typeof o.voices === 'string' ? voiceList(o.voices) : [],
  }
}

// The module's own session state (a reload starts it over, which only forgets a /hush).
let cfg: Config
let claude: { tty: string; pid: string } | null = null
let home = ''
/** This session's own voice, claimed at start (unused when a fixed voice is set). */
let sessionVoice = ''
let inGhostty = false
let muted = false
let lastRequest = ''
let lastAnswer = ''
let todos: Todo[] = []
let checkin: { cancel(): void } | undefined
let turnStartedAt = 0
const warned = new Set<string>()

// "<tty> <pid>" of the nearest ancestor owning a terminal: Claude itself. The pid gives the session its voice.
const FIND_CLAUDE = `p=$$
while [ "$p" -gt 1 ]; do
  t=$(ps -o tty= -p "$p" | tr -d ' ')
  case "$t" in ''|'?'|'??') p=$(ps -o ppid= -p "$p" | tr -d ' ') ;; *) echo "$t $p"; exit ;; esac
done`

// The tty of the terminal Ghostty has focused, or nothing when Ghostty isn't the frontmost app.
const FOCUSED_TTY = `tell application "Ghostty"
  if frontmost then return tty of focused terminal of selected tab of front window
  return ""
end tell`

async function locate($: EngineInterface) {
  const found = (await $.process.run(['sh', '-c', `${FIND_CLAUDE}\necho "$TERM_PROGRAM"\necho "$HOME"`])).stdout.trim().split('\n')
  const [tty, pid] = (found[0] ?? '').split(' ')
  claude = tty && pid ? { tty, pid } : null
  inGhostty = (found[1] ?? '').toLowerCase() === 'ghostty'
  home = found[2] ?? ''
}

// Every running session shares one small table of who speaks with which voice.
async function claimSessionVoice($: EngineInterface) {
  if (!claude || !home) return
  const dir = `${home}/Library/Caches/murmur-claude`
  const file = `${dir}/voices.json`
  const table = parseTable(await $.fs.read(file).catch(() => ''))
  const pids = Object.keys(table)
  const alive = pids.length
    ? (await $.process.run(['sh', '-c', 'for p; do kill -0 "$p" 2>/dev/null && echo "$p"; done', 'sh', ...pids])).stdout.split('\n')
    : []
  const claimed = claimVoice(table, claude.pid, new Set(alive), cfg.voices)
  sessionVoice = claimed.voice
  // ponytail: last writer wins; two sessions starting in the same instant can share a voice until one restarts.
  await $.process.run(['mkdir', '-p', dir])
  await $.fs.write(file, JSON.stringify(claimed.table))
}

// Quiet by default: speak only when this terminal isn't the one in front of you.
async function isAway($: EngineInterface): Promise<boolean> {
  if (cfg.speakWhen === 'always' || !inGhostty || !claude) return true  // can't tell: the other gates decide
  const r = await $.process.run(['osascript', '-e', FOCUSED_TTY])
  return r.exitCode !== 0 || r.stdout.trim() !== `/dev/${claude.tty}`
}

// Interrupt, don't stack: each new line cuts off whatever is still playing.
async function say($: EngineInterface, text: string, always = false) {
  if (muted || !text.trim() || (!always && !(await isAway($)))) return
  const argv = ['murmur', '--interrupt', '--speed', String(cfg.speed)]
  const voice = cfg.voice || sessionVoice
  if (voice) argv.push('--voice', voice)
  const r = await $.process.run([...argv, '--', text]).catch(() => null)
  if (r && r.exitCode !== 0) $.ui.toast(`murmur: ${r.stderr.trim().slice(0, 120) || 'failed'}`)
}

async function summarize($: EngineInterface, request: string, answer: string): Promise<string> {
  if (cfg.summaryStyle === 'first-sentence') return firstSentence(answer)
  const r = await $.model.complete({ model: 'haiku', prompt: summaryPrompt(request, answer), maxTokens: 60 })
  const line = r.isAnswered ? prose(r.text).replace(/\s+/g, ' ').trim() : ''
  return line && line.length <= 200 ? line : firstSentence(answer)
}

async function checkIn($: EngineInterface) {
  const minutes = Math.round((Date.now() - turnStartedAt) / 60000)
  await say($, checkinLine(todos, minutes))
}

function stopCheckins() {
  checkin?.cancel()
  checkin = undefined
}

export const register: Register = (on, options) => {
  cfg = config(options)
  // Hooks that gate a prompt or a tool call pass it on untouched if they fail: speech must never block work.

  on('session.start', async ($, e, next) => {
    await locate($)
    if (!cfg.voice) await claimSessionVoice($).catch(() => {})
    await $.command.register({ name: 'hush', description: 'Mute or unmute spoken updates for this session' })
    await $.command.register({ name: 'read', description: "Read Claude's last answer aloud" })
    await $.command.register({ name: 'tldr-aloud', description: 'Hear a 2–3 sentence summary of this session' })
    return next(e)
  })

  // Every turn starts here: its request, a fresh todo list, and the check-in timer.
  on('prompt.submit', async ($, e, next) => {
    stopCheckins()
    todos = []
    turnStartedAt = Date.now()
    if (e.origin.kind === 'task-notification') {
      if (cfg.backgroundTasks) void say($, taskLine(e.text))
    } else {
      lastRequest = e.text
    }
    if (cfg.checkins) checkin = $.clock.every(cfg.checkinMinutes * 60_000, () => void checkIn($))
    return next(e)
  }).catch(($, e, next) => next(e))

  on('tool.call', { tool: 'TodoWrite' }, ($, e, next) => {
    todos = e.todos.map(t => ({ ...t }))
    return next(e)
  }).catch(($, e, next) => next(e))

  on('tool.call', { tool: 'AskUserQuestion' }, ($, e, next) => {
    if (cfg.needsYou) void say($, 'Claude has a question for you.')
    return next(e)
  }).catch(($, e, next) => next(e))

  // Permission prompts reach mods as Claude Code's Notification hook event.
  on('classic.Notification', ($, e, next) => {
    if (cfg.needsYou && e.notification_type === 'permission_prompt') {
      void say($, prose(e.message) || 'Claude needs your permission.')
    }
    return next(e)
  }).catch(($, e, next) => next(e))

  on('turn.complete', async ($, e, next) => {
    if (e.agentId) return next(e)
    stopCheckins()
    lastAnswer = e.answer
    const isLong = e.durationMs >= cfg.minTurnSeconds * 1000
    if (cfg.turnSummaries && e.reason === 'answer' && isLong && !muted) {
      const request = lastRequest
      void summarize($, request, e.answer).then(line => say($, line))
    }
    return next(e)
  })

  on('session.measure', async ($, e, next) => {
    if (cfg.rateLimitWarnings) {
      for (const w of e.rateLimits) {
        const key = `${w.kind}@${w.resetsAt ?? ''}`
        if (w.percentUsed >= cfg.rateLimitPercent && !warned.has(key)) {
          warned.add(key)
          void say($, rateLimitLine(w.kind, w.percentUsed))
        }
      }
    }
    return next(e)
  })

  on('command.run', { command: 'hush' }, async $ => {
    muted = !muted
    if (muted) await $.process.run(['murmur', 'stop']).catch(() => null)
    return { text: muted ? '🔇 Spoken updates muted for this session. /hush again to unmute.' : '🔊 Spoken updates back on.' }
  })

  on('command.run', { command: 'read' }, async $ => {
    if (!lastAnswer) return { text: 'Nothing to read yet.' }
    if (muted) return { text: 'Muted: /hush to unmute first.' }
    void say($, prose(lastAnswer, 'Code omitted.'), true)
    return { text: '🔊 Reading the last answer aloud. /hush stops it.' }
  })

  on('command.run', { command: 'tldr-aloud' }, async $ => {
    if (muted) return { text: 'Muted: /hush to unmute first.' }
    const r = await $.model.fork({
      prompt: 'In 2 or 3 short sentences meant to be spoken aloud, summarize this session so far: the goal, what is done, and what is next. Plain words only, no markdown or code.',
    })
    if (!r.isAnswered) return { text: `Couldn't summarize: ${r.reason}` }
    const line = prose(r.text).replace(/\s+/g, ' ').trim()
    void say($, line, true)
    return { text: `🔊 ${line}` }
  })
}
