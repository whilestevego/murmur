import { test, expect } from 'claude-code/testing'

import { checkinLine, firstSentence, prose, rateLimitLine, summaryPrompt, taskLine, voiceList } from './speech'

test('prose strips markdown and can name code', () => {
  expect(prose('I fixed the **login** bug in `auth.ts`.')).toBe('I fixed the login bug in auth.ts.')
  expect(prose('See [docs](http://x).\n```ts\nx()\n```\n- one\n- two', 'Code omitted.')).toBe('See docs.\n Code omitted. \none\ntwo')
  expect(prose('| a | b |\n|---|---|\nAfter')).toBe('After')
})

test('firstSentence', () => {
  expect(firstSentence('Fixed it. Then tested.')).toBe('Fixed it.')
  expect(firstSentence('x'.repeat(200))).toBe('Done.')
  expect(firstSentence('```only code```')).toBe('Done.')
})

test('summaryPrompt bounds its inputs', () => {
  expect(summaryPrompt('a'.repeat(5000), 'b'.repeat(9000)).length).toBeLessThan(5000)
})

test('taskLine', () => {
  expect(taskLine('<task-notification><status>completed</status><summary>Tests **passed**: 42</summary></task-notification>'))
    .toBe('Background task: Tests passed: 42')
  expect(taskLine('<status>failed</status>')).toBe('A background task failed.')
  expect(taskLine('whatever')).toBe('A background task finished.')
})

test('checkinLine', () => {
  expect(checkinLine([], 5)).toBe('Still working, 5 minutes in.')
  expect(checkinLine([
    { content: 'a', status: 'completed', activeForm: 'Doing a' },
    { content: 'b', status: 'in_progress', activeForm: 'Writing the tests' },
    { content: 'c', status: 'pending', activeForm: 'Doing c' },
  ], 1)).toBe('Still working, 1 minute in. Writing the tests. 1 of 3 steps done.')
})

test('rateLimitLine and voiceList', () => {
  expect(rateLimitLine('five_hour', 90.4)).toBe("Heads up: you've used 90 percent of your five hour limit.")
  expect(voiceList(' af_heart, bm_george ,')).toEqual(['af_heart', 'bm_george'])
  expect(voiceList('')).toEqual([])
})
