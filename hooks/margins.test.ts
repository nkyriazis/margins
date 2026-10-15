import { expect, mock, test } from 'claude-code/testing'

const NOW = 1792047075
const LOG = (lines: string[][]) => lines.map((l) => l.join('\t')).join('\n') + '\n'
const OPEN = LOG([
  ['1792047000', 'open', '/work/plan.md', '1'],
  ['1792047001', 'watch', '/work/plan.md', '4242 4026531836'],
  ['1792047030', 'save', '/work/plan.md', '1'],
  ['1792047033', 'turn', '/work/plan.md', '2'],
  ['1792047040', 'reply', '/work/plan.md', '3'],
])

// Answer everything the mod asks Claude Code for, with this state on disk
function world(on, text: string, opts: { alive?: boolean } = {}) {
  const clock = mock.clock(on, { now: NOW * 1000 })
  mock.env(on, { XDG_RUNTIME_DIR: '/run/user/1000' })
  on('session.start', () => ({ cwd: '/work' }))
  on('session.id', () => ({ value: 'abc-123' }))
  on('fs.exists', ($, e) => ({ value: e.path.startsWith('/proc/') ? opts.alive !== false || e.path === '/proc/self/stat' : true }))
  on('fs.stat', ($, e) =>
    e.path === '/run/user/1000/margins/abc-123.log'
      ? { value: { kind: 'file', size: text.length, mtimeMs: 1, isLink: false } }
      : { deny: 'ENOENT' },
  )
  on('fs.read', () => ({ value: text }))
  on('process.run', ($, e) => ({ value: { exitCode: 0, stdout: e.argv[0] === 'readlink' ? 'pid:[4026531836]\n' : '1000\n', stderr: '' } }))
  on('ui.render', () => ({ type: 'Text', props: {}, children: [''] }))
  return clock
}

const BAND = {
  plugin: 'margins',
  component: 'AbovePrompt',
  requestId: 'band',
  surface: 'terminal',
  viewport: { columns: 100, rows: 30 },
  props: { hasSurvey: false, isWorking: false, maxRows: 12, bodyColumns: 100, scroll: { offset: 0, bodyRows: 11 }, view: {} },
} as const

async function band($, clock, working = false) {
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
  await clock.advance(1000)
  return $.ui.mount({ ...BAND, props: { ...BAND.props, isWorking: working } })
}

test('a watched dialog waiting on the author says so', async ($, on) => {
  const ui = await band($, world(on, OPEN))
  expect(await ui.find({ type: 'Text', text: /plan\.md/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /turn 3/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /your turn/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /watching/ })).toBeDefined()
})

test('a dialog whose watch died is flagged', async ($, on) => {
  const ui = await band($, world(on, OPEN, { alive: false }))
  expect(await ui.find({ type: 'Text', text: /not watched/ })).toBeDefined()
})

test('a save shows until Claude takes the turn', async ($, on) => {
  const saved = OPEN + LOG([['1792047060', 'save', '/work/plan.md', '3']])
  const ui = await band($, world(on, saved))
  expect(await ui.find({ type: 'Text', text: /you saved/ })).toBeDefined()
})

test('Claude holds the turn only while it works', async ($, on) => {
  const taken = OPEN + LOG([['1792047060', 'turn', '/work/plan.md', '4']])
  const ui = await band($, world(on, taken), true)
  expect(await ui.find({ type: 'Text', text: /Claude is answering/ })).toBeDefined()
})

test('a closed dialog shows until the next prompt', async ($, on) => {
  const closed = OPEN + LOG([['1792047070', 'closed', '/work/plan.md', '5']])
  const ui = await band($, world(on, closed))
  expect(await ui.find({ type: 'Text', text: /closed after 5 turns/ })).toBeDefined()
})

test('nothing shows without a dialog', async ($, on) => {
  const ui = await band($, world(on, ''))
  expect(await ui.find({ type: 'Text', text: /plan\.md/ })).toBeUndefined()
})

test('a typed prompt clears a closed dialog, a notification does not', async ($, on) => {
  const closed = OPEN + LOG([['1792047070', 'closed', '/work/plan.md', '5']])
  const clock = world(on, closed)
  on('prompt.submit', () => ({ text: 'ok' }))
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
  await clock.advance(1000)
  await clock.advance(10_000)
  await $.prompt.submit({ text: 'the watch ended', origin: { kind: 'task-notification' } })
  let ui = await $.ui.mount(BAND)
  expect(await ui.find({ type: 'Text', text: /closed after 5 turns/ })).toBeDefined()
  await $.prompt.submit({ text: 'thanks', origin: { kind: 'composer' } })
  ui = await $.ui.mount({ ...BAND, requestId: 'band2' })
  expect(await ui.find({ type: 'Text', text: /closed after 5 turns/ })).toBeUndefined()
})
