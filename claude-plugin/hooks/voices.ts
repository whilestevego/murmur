// One voice per running Claude session, claimed from a small table every session shares.

/** Voices handed to sessions in turn: alternating accents and genders so neighbours sound distinct. */
export const SESSION_VOICES = [
  'af_heart', 'bm_george', 'af_nicole', 'am_michael', 'bf_emma', 'am_fenrir',
  'bf_isabella', 'bm_fable', 'af_bella', 'am_santa', 'bf_lily', 'bm_lewis',
]

/** Session (process id) → voice. */
export type VoiceTable = Record<string, string>

/**
 * This session's voice: the one it already holds, else the first in `pool` no other live session holds
 * (cycling once every voice is taken). Sessions not in `alive` are dropped, freeing their voices.
 */
export function claimVoice(table: VoiceTable, me: string, alive: ReadonlySet<string>, pool: readonly string[]) {
  const live: VoiceTable = Object.fromEntries(Object.entries(table).filter(([pid]) => pid === me || alive.has(pid)))
  const held = live[me]
  if (held) return { voice: held, table: live }
  const choices = pool.length ? pool : SESSION_VOICES
  const taken = new Set(Object.values(live))
  const voice = choices.find(v => !taken.has(v)) ?? choices[Object.keys(live).length % choices.length]!
  return { voice, table: { ...live, [me]: voice } }
}

/** The shared table file's text → a table; anything unreadable is an empty table. */
export function parseTable(text: string): VoiceTable {
  try {
    const data: unknown = JSON.parse(text)
    if (!data || typeof data !== 'object' || Array.isArray(data)) return {}
    return Object.fromEntries(Object.entries(data).filter((kv): kv is [string, string] => typeof kv[1] === 'string'))
  } catch {
    return {}
  }
}
