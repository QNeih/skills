import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'

const HOUR = 60 * 60 * 1000
const MINUTE = 60 * 1000
const START = 1_000_000_000_000

function world(on: On, entries?: Record<string, unknown>) {
  const clock = mock.clock(on, { now: START })
  mock.store(on, entries)
  const opened: string[] = []
  const closed: string[] = []
  on('command.register', () => ({ value: { command: 'break' } }))
  on('ui.open', (_, e) => {
    opened.push(e.id)
    return { value: { isPlaced: true } }
  })
  on('ui.close', (_, e) => {
    closed.push(e.id)
    return { value: undefined }
  })
  on('ui.toast', () => ({ value: undefined }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  return { clock, opened, closed }
}

const session = { cwd: '/', surface: 'desktop', isInteractive: true } as const

test('opens the reminder each hour, Done closes it, on every surface', async ($, on) => {
  const { clock, opened, closed } = world(on)

  await $.session.start(session)
  await clock.advance(HOUR - MINUTE)
  expect(opened).toHaveLength(0)
  await clock.advance(MINUTE)
  expect(opened).toEqual(['break-reminder'])
  await clock.advance(HOUR)
  expect(opened).toHaveLength(2)

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({
      plugin: 'break-reminder',
      surface,
      component: 'Pane',
      requestId: 'break-reminder',
      props: {
        title: '☕ Break',
        isFocused: false,
        bodyColumns: 40,
        placement: 'dock',
        scroll: { offset: 0, bodyRows: 20 },
        view: {},
      },
    })
    expect((await ui.find({ type: 'Text', text: /water/ }))?.text).toBe('Time to stretch 🧘 and drink water 💧')
    await ui.press({ key: 'done' })
    await ui.unmount()
  }
  expect(closed).toEqual(['break-reminder', 'break-reminder'])
})

test('a new session keeps the hour that earlier sessions started', async ($, on) => {
  const { clock, opened } = world(on, { lastReminderAt: START - 50 * MINUTE })

  await $.session.start(session)
  await clock.advance(9 * MINUTE)
  expect(opened).toHaveLength(0)
  await clock.advance(MINUTE)
  expect(opened).toHaveLength(1)
})

test('two open sessions share one reminder per hour', async ($, on) => {
  const { clock, opened } = world(on)

  await $.session.start(session)
  await clock.advance(30 * 1000)
  await $.session.start(session)
  await clock.advance(2 * HOUR)
  expect(opened).toHaveLength(2)
})
