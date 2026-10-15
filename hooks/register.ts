// margins as a Claude Code mod: a band above the prompt with one row per
// dialog this session holds, saying whose turn it is and whether the file is
// watched, redrawn from the session's state file once a second.
//
// MARGINS_BAND=0 turns it off.
import { parse, row, type Dialog, type Seg } from './dialogs.ts'

let sid = ''
let file = ''
let seen = -1
let busy = false
let show = true
let hasProc = false
let ownNs = ''
let dialogs: Dialog[] = []
let live = new Set<string>()
let checked = 0
// Closed dialogs leave the band at the first prompt after they closed.
let promptedAt = 0

// The session's state file, resolved the way margins.sh resolves it
async function locate($) {
  show = (await $.env.get('MARGINS_BAND')) !== '0'
  hasProc = await $.fs.exists('/proc/self/stat')
  let dir = (await $.env.get('MARGINS_DIR')) ?? ''
  if (dir === '') {
    const xdg = (await $.env.get('XDG_RUNTIME_DIR')) ?? ''
    if (xdg !== '' && (await $.fs.exists(xdg))) {
      dir = xdg + '/margins'
    } else {
      const tmp = (await $.env.get('TMPDIR')) || '/tmp'
      const id = await $.process.run(['id', '-u'])
      dir = tmp.replace(/\/$/, '') + '/margins-' + id.stdout.trim()
    }
  }
  if (hasProc) {
    const link = await $.process.run(['readlink', '/proc/self/ns/pid'])
    ownNs = link.stdout.replace(/[^0-9]/g, '')
  }
  file = dir + '/' + sid.replace(/[^A-Za-z0-9._-]/g, '_') + '.log'
  seen = -1
  dialogs = []
}

// A watch whose process is gone no longer sees saves. Across pid namespaces
// (a sandbox) the pid means nothing here, so it counts as alive.
async function alive($, d: Dialog): Promise<boolean> {
  if (!d.pid) return false
  if (d.ns && ownNs && d.ns !== ownNs) return true
  if (hasProc) return $.fs.exists('/proc/' + d.pid)
  const r = await $.process.run(['kill', '-0', d.pid])
  return r.exitCode === 0
}

async function refresh($) {
  if (busy) return
  busy = true
  try {
    await tick($)
  } finally {
    busy = false
  }
}

async function tick($) {
  const now = (await $.clock.now()) / 1000
  const id = String(await $.session.id())
  if (id !== sid) {
    sid = id
    await locate($)
  }
  const stat = await $.fs.stat(file).catch(() => undefined)
  let changed = false
  if (!stat) {
    changed = dialogs.length > 0
    dialogs = []
  } else if (stat.mtimeMs !== seen) {
    seen = stat.mtimeMs
    dialogs = parse(await $.fs.read(file).catch(() => ''))
    changed = true
  }
  if (dialogs.length > 0 && (changed || now - checked >= 2)) {
    checked = now
    const next = new Set<string>()
    for (const d of dialogs) if (await alive($, d)) next.add(d.path)
    if (next.size !== live.size || [...next].some((p) => !live.has(p))) changed = true
    live = next
  }
  if (changed) $.ui.invalidate('ui.render')
}

const shown = () => dialogs.filter((d) => d.phase !== 'closed' || d.at >= promptedAt)

export function register(on) {
  on('session.start', async ($, e, next) => {
    $.clock.every(1000, () => refresh($))
    return next(e)
  })

  on('prompt.submit', async ($, e, next) => {
    try {
      promptedAt = (await $.clock.now()) / 1000
      if (dialogs.some((d) => d.phase === 'closed')) $.ui.invalidate('ui.render')
    } catch {
      // The band is a courtesy; the prompt goes through regardless.
    }
    return next(e)
  })

  // One row per dialog, with anything other mods draw there kept below.
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const rows = shown()
    if (!show || rows.length === 0 || e.props.hasSurvey) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    const draw = (seg: Seg) =>
      seg.color || seg.dim || seg.bold
        ? Text({ color: seg.color, dimColor: seg.dim, bold: seg.bold, children: [seg.text] })
        : seg.text
    const room = Math.max(1, e.props.maxRows - 1)
    const lines = rows
      .slice(-room)
      .map((d) => Text({ wrap: 'truncate-end', children: row(d, live.has(d.path), e.props.isWorking).map(draw) }))
    const theirs = await next(e)
    return Box({ flexDirection: 'column', children: theirs ? [...lines, theirs] : lines })
  })
}
