// Turning Claude's markdown into something worth hearing.

/** Markdown → plain spoken prose. Code blocks become `codeAs` (dropped when empty). */
export function prose(markdown: string, codeAs = ''): string {
  return markdown
    .replace(/```[\s\S]*?```/g, codeAs ? ` ${codeAs} ` : ' ')
    .replace(/`([^`\n]*)`/g, '$1')
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/^\s*[-*+]\s+/gm, '')
    .replace(/^\s*\|.*\|\s*$/gm, '')
    .replace(/[*_#>|~]/g, '')
    .replace(/[ \t]+/g, ' ')
    .replace(/\n{2,}/g, '\n')
    .trim()
}

/** The first sentence when it reads well spoken, else `fallback`. */
export function firstSentence(markdown: string, fallback = 'Done.'): string {
  const text = prose(markdown).replace(/\s+/g, ' ')
  const first = text.match(/^.*?[.!?](?=\s|$)/)?.[0] ?? text
  return first.length >= 3 && first.length <= 160 ? first : fallback
}

/** The prompt that turns a finished turn into one spoken line. */
export function summaryPrompt(request: string, answer: string): string {
  return [
    'A coding assistant just finished a task. In ONE short sentence of at most 15 words, meant to be',
    'spoken aloud to the developer, say what was done and whether anything needs their attention.',
    'Plain words only: no markdown, code, file paths or quotes.',
    '',
    `Request: ${request.slice(0, 1500)}`,
    `Answer: ${answer.slice(0, 3000)}`,
  ].join('\n')
}

/** A background task's notification text → what to say. */
export function taskLine(text: string): string {
  const summary = text.match(/<summary>([\s\S]*?)<\/summary>/)?.[1]?.trim()
  const status = text.match(/<status>([\s\S]*?)<\/status>/)?.[1]?.trim()
  const what = summary ? prose(summary).replace(/\s+/g, ' ').slice(0, 140) : ''
  if (what) return `Background task: ${what}`
  return status === 'failed' ? 'A background task failed.' : 'A background task finished.'
}

export type Todo = { content: string; status: 'pending' | 'in_progress' | 'completed'; activeForm: string }

/** The progress check-in: what's in progress and how far along the list is. */
export function checkinLine(todos: readonly Todo[], minutes: number): string {
  const elapsed = `Still working, ${minutes} minute${minutes === 1 ? '' : 's'} in.`
  if (todos.length === 0) return elapsed
  const done = todos.filter(t => t.status === 'completed').length
  const now = todos.find(t => t.status === 'in_progress')
  return `${elapsed} ${now ? `${now.activeForm}. ` : ''}${done} of ${todos.length} steps done.`
}

export function rateLimitLine(kind: string, percent: number): string {
  const name = ({ five_hour: 'five hour', seven_day: 'weekly', spend_limit: 'spend' } as Record<string, string>)[kind] ?? kind
  return `Heads up: you've used ${Math.round(percent)} percent of your ${name} limit.`
}

/** "af_heart, bm_george" → ["af_heart", "bm_george"]; empty → []. */
export function voiceList(option: string): string[] {
  return option.split(',').map(v => v.trim()).filter(Boolean)
}
