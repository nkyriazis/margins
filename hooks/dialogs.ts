// The state file margins.sh appends to, read back as one entry per dialog.
// Each line is `<epoch> TAB <event> TAB <absolute path> TAB <detail>`.

export type Phase = 'yours' | 'saved' | 'claude' | 'closed'

export type Dialog = {
  path: string
  name: string
  phase: Phase
  turn: number
  // The watch armed last, while it has not said it ended
  pid: string
  ns: string
  at: number
}

export type Seg = { text: string; color?: string; dim?: boolean; bold?: boolean }

export function parse(text: string): Dialog[] {
  const byPath = new Map<string, Dialog>()
  for (const line of text.split('\n')) {
    const [at, event, path, detail = ''] = line.split('\t')
    if (!path) continue
    let d = byPath.get(path)
    if (!d) {
      d = { path, name: path.split('/').pop() ?? path, phase: 'yours', turn: 0, pid: '', ns: '', at: 0 }
      byPath.set(path, d)
    }
    d.at = Number(at) || d.at
    const n = Number(detail)
    switch (event) {
      case 'open':
      case 'reply':
        d.phase = 'yours'
        break
      case 'save':
        d.phase = 'saved'
        break
      case 'turn':
        d.phase = 'claude'
        break
      case 'closed':
        d.phase = 'closed'
        d.pid = ''
        break
      case 'watch': {
        const [pid = '', ns = ''] = detail.split(' ')
        d.pid = pid
        d.ns = ns
        if (d.phase === 'closed') d.phase = 'yours'
        continue
      }
      case 'unwatch':
        if (d.pid === detail) d.pid = ''
        continue
      default:
        continue
    }
    if (event !== 'save' && Number.isFinite(n) && detail !== '') d.turn = n
  }
  return [...byPath.values()]
}

// One row of the band: what the dialog waits for, and whether a save will be seen.
export function row(d: Dialog, watching: boolean, working: boolean): Seg[] {
  const head: Seg[] = [
    { text: d.phase === 'closed' ? '✔ ' : '✎ ', color: d.phase === 'closed' ? 'green' : 'magenta' },
    { text: d.name, bold: d.phase !== 'closed', dim: d.phase === 'closed' },
  ]
  if (d.phase === 'closed') {
    return [...head, { text: ` · closed after ${d.turn} turns`, dim: true }]
  }
  const segs: Seg[] = [...head, { text: ` · turn ${d.turn} · `, dim: true }]
  // A turn that needed no reply leaves no event behind, so Claude only holds
  // the turn while it is working.
  if (d.phase === 'yours' || (d.phase === 'claude' && !working)) segs.push({ text: 'your turn', color: 'green' })
  if (d.phase === 'saved') segs.push({ text: 'you saved, Claude is reading', color: 'yellow' })
  if (d.phase === 'claude' && working) segs.push({ text: 'Claude is answering in the file', color: 'cyan' })
  segs.push({ text: ' · ', dim: true })
  segs.push(watching ? { text: 'watching', dim: true } : { text: 'not watched, a save goes unanswered', color: 'red' })
  return segs
}
