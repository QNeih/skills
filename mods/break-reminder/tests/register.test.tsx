import { expect, mock, test } from 'claude-code/testing'

const HOUR = 60 * 60 * 1000

test('opens the reminder each hour, Done closes it, on every surface', async ($, on) => {
  const clock = mock.clock(on)
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

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await clock.advance(HOUR - 1)
  expect(opened).toHaveLength(0)
  await clock.advance(1)
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
