import { test, expect, mock } from 'claude-code/testing'
import type { On } from 'claude-code'

// The test environment has timers; the plugin typings (no DOM, no Node) just don't declare them.
declare function setTimeout(fn: (value?: unknown) => void, ms: number): unknown

/**
 * Fakes the machine: Claude on ttys004 (pid 4242) in Ghostty, `focused` deciding what osascript reports,
 * `files` the disk, `alive` which other sessions still run.
 */
function machine(on: On, focused: { tty: string }, files: Record<string, string> = {}, alive: string[] = []) {
  const spoken: string[][] = []
  on('process.run', (_$, e) => {
    const argv = e.argv as string[]
    const out = (stdout: string) => ({ value: { exitCode: 0, stdout, stderr: '' } }) as never
    if (argv[0] === 'sh' && argv[2]?.includes('kill -0')) return out(argv.slice(4).filter(p => alive.includes(p)).join('\n'))
    if (argv[0] === 'sh') return out('ttys004 4242\nghostty\n/home/me\n')
    if (argv[0] === 'osascript') return out(focused.tty)
    if (argv[0] === 'murmur') spoken.push(argv)
    return out('')
  })
  on('fs.read', (_$, e) => {
    const path = (e as unknown as { path: string }).path
    return (path in files ? { value: files[path] } : { deny: 'no such file' }) as never
  })
  on('fs.write', (_$, e) => {
    const { path, text } = e as unknown as { path: string; text: string }
    files[path] = text
    return { value: undefined } as never
  })
  on('command.register', () => ({ value: {} }) as never)
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  on('turn.complete', (_$, e) => ({ text: e.answer }))
  on('command.run', () => ({ text: '' }))
  on('classic.Notification', () => ({}))
  on('prompt.submit', (_$, e) => ({ text: e.text }) as never)
  on('session.measure', (_$, e) => ({ changed: e.changed }) as never)
  return spoken
}

const TABLE = '/home/me/Library/Caches/murmur-claude/voices.json'
const start = { cwd: '/', surface: 'terminal' as const, isInteractive: true }
const turn = (durationMs: number, answer: string) =>
  ({ answer, durationMs, isAborted: false, turnId: 't', reason: 'answer' }) as never
const settle = () => new Promise(r => setTimeout(r, 20))

test('a long turn is summarized in this session own voice; a short one is not', { options: { summaryStyle: 'first-sentence' } }, async ($, on) => {
  const spoken = machine(on, { tty: '' })
  await $.session.start(start)
  await $.turn.complete(turn(5_000, 'Quick one.'))
  await $.turn.complete(turn(60_000, 'Fixed the login bug. Details follow.'))
  await settle()
  expect(spoken).toHaveLength(1)
  expect(spoken[0]).toEqual(['murmur', '--interrupt', '--speed', '1', '--voice', 'af_heart', '--', 'Fixed the login bug.'])
})

test('quiet by default: nothing is said while this terminal is focused', { options: { summaryStyle: 'first-sentence' } }, async ($, on) => {
  const focus = { tty: '/dev/ttys004' }
  const spoken = machine(on, focus)
  await $.session.start(start)
  await $.turn.complete(turn(60_000, 'Done here.'))
  await settle()
  expect(spoken).toHaveLength(0)
  focus.tty = '/dev/ttys009'  // you switched to another tab
  await $.turn.complete(turn(60_000, 'Done here.'))
  await settle()
  expect(spoken).toHaveLength(1)
})

test('/hush mutes everything until run again', { options: { summaryStyle: 'first-sentence' } }, async ($, on) => {
  const spoken = machine(on, { tty: '' })
  await $.session.start(start)
  expect((await $.command.run({ command: 'hush' } as never)).text).toContain('muted')
  await $.turn.complete(turn(60_000, 'Muted answer.'))
  await settle()
  expect(spoken.filter(a => a[1] !== 'stop')).toHaveLength(0)
  await $.command.run({ command: 'hush' } as never)
  await $.turn.complete(turn(60_000, 'Heard answer.'))
  await settle()
  expect(spoken.at(-1)?.at(-1)).toBe('Heard answer.')
})

test('/read says the whole last answer with code omitted, even when focused', async ($, on) => {
  const spoken = machine(on, { tty: '/dev/ttys004' })
  await $.session.start(start)
  await $.turn.complete(turn(1_000, 'Here:\n```js\nx()\n```\nThat is all.'))
  await $.command.run({ command: 'read' } as never)
  await settle()
  expect(spoken.at(-1)?.at(-1)).toBe('Here:\n Code omitted. \nThat is all.')
})

test('a permission prompt is announced', async ($, on) => {
  const spoken = machine(on, { tty: '' })
  await $.session.start(start)
  await $.classic.Notification({ message: 'Claude needs your permission to use Bash', notification_type: 'permission_prompt' } as never)
  await settle()
  expect(spoken.at(-1)?.at(-1)).toBe('Claude needs your permission to use Bash')
})

test('a fixed voice wins over the session voice, and claims nothing', { options: { voice: 'bf_emma', summaryStyle: 'first-sentence' } }, async ($, on) => {
  const files: Record<string, string> = {}
  const spoken = machine(on, { tty: '' }, files)
  await $.session.start(start)
  await $.turn.complete(turn(60_000, 'Voice check.'))
  await settle()
  expect(spoken[0]).toEqual(['murmur', '--interrupt', '--speed', '1', '--voice', 'bf_emma', '--', 'Voice check.'])
  expect(files[TABLE]).toBeUndefined()
})

test('a second live session gets the next voice; a dead one gives its voice back', { options: { summaryStyle: 'first-sentence' } }, async ($, on) => {
  const files: Record<string, string> = { [TABLE]: JSON.stringify({ 1111: 'af_heart', 2222: 'bm_george' }) }
  const spoken = machine(on, { tty: '' }, files, ['1111'])  // 2222 has exited
  await $.session.start(start)
  await $.turn.complete(turn(60_000, 'Hello.'))
  await settle()
  expect(spoken[0]).toContain('bm_george')
  expect(JSON.parse(files[TABLE]!)).toEqual({ 1111: 'af_heart', 4242: 'bm_george' })
})

test('the session voice comes from the configured list', { options: { voices: 'bm_lewis, af_sky', summaryStyle: 'first-sentence' } }, async ($, on) => {
  const spoken = machine(on, { tty: '' })
  await $.session.start(start)
  await $.turn.complete(turn(60_000, 'Hi.'))
  await settle()
  expect(spoken[0]).toContain('bm_lewis')
})

test('a finished background task is announced', async ($, on) => {
  const spoken = machine(on, { tty: '' })
  await $.session.start(start)
  await $.prompt.submit({ text: '<task-notification><status>completed</status><summary>All 42 tests passed</summary></task-notification>', origin: { kind: 'task-notification' } } as never)
  await settle()
  expect(spoken.at(-1)?.at(-1)).toBe('Background task: All 42 tests passed')
})

test('a rate limit is warned about once per window', async ($, on) => {
  const spoken = machine(on, { tty: '' })
  await $.session.start(start)
  const measure = (percentUsed: number) =>
    $.session.measure({ context: {}, rateLimits: [{ kind: 'five_hour', percentUsed, resetsAt: 'R1' }], changed: ['rateLimits'] } as never)
  await measure(85)
  await measure(91)
  await measure(95)
  await settle()
  expect(spoken.map(a => a.at(-1))).toEqual(["Heads up: you've used 91 percent of your five hour limit."])
})

test('long turns check in with the todo in progress', { options: { checkinMinutes: 1 } }, async ($, on) => {
  const clock = mock.clock(on)
  const spoken = machine(on, { tty: '' })
  on('tool.call', () => ({ result: {}, text: '' }) as never)
  await $.session.start(start)
  await $.prompt.submit({ text: 'Build it', origin: { kind: 'user' } } as never)
  await $.tool.call({ tool: 'TodoWrite', todos: [
    { content: 'a', status: 'completed', activeForm: 'Planning' },
    { content: 'b', status: 'in_progress', activeForm: 'Writing the parser' },
  ] } as never)
  await clock.advance(60_000)
  await settle()
  expect(spoken.at(-1)?.at(-1)).toMatch(/^Still working, \d+ minutes? in\. Writing the parser\. 1 of 2 steps done\.$/)
})
