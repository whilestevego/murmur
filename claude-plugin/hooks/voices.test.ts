import { test, expect } from 'claude-code/testing'

import { claimVoice, parseTable, SESSION_VOICES } from './voices'

const pool = ['a', 'b', 'c']

test('sessions get distinct voices and keep them', () => {
  let table = {}
  const voices = ['10', '20', '30'].map(me => {
    const r = claimVoice(table, me, new Set(Object.keys(table)), pool)
    table = r.table
    return r.voice
  })
  expect(voices).toEqual(['a', 'b', 'c'])
  expect(claimVoice(table, '20', new Set(['10', '20', '30']), pool).voice).toBe('b')
})

test('a closed session frees its voice', () => {
  const r = claimVoice({ 10: 'a', 20: 'b' }, '30', new Set(['20']), pool)
  expect(r.voice).toBe('a')
  expect(r.table).toEqual({ 20: 'b', 30: 'a' })
})

test('voices cycle once all are taken; an empty pool means the default mix', () => {
  expect(claimVoice({ 1: 'a', 2: 'b', 3: 'c' }, '4', new Set(['1', '2', '3']), pool).voice).toBe('a')
  expect(claimVoice({}, '1', new Set(), []).voice).toBe(SESSION_VOICES[0])
})

test('parseTable tolerates junk', () => {
  expect(parseTable('{"1":"a","2":3}')).toEqual({ 1: 'a' })
  expect(parseTable('not json')).toEqual({})
  expect(parseTable('[1]')).toEqual({})
})
