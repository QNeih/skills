import type { Register } from 'claude-code'

const PANE = 'break-reminder'
const HOUR = 60 * 60 * 1000
const MINUTE = 60 * 1000
const LAST_AT = 'lastReminderAt'
const WARM = '#D9895B'

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'break',
      description: 'Show the drink-and-stretch reminder now',
    })
    // The schedule lives in the store, shared by every session, so one
    // reminder goes out per hour however many sessions are open or restarted.
    if ((await $.store.get(LAST_AT)) === undefined) {
      await $.store.set(LAST_AT, await $.clock.now())
    }
    $.clock.every(MINUTE, async () => {
      const now = await $.clock.now()
      if (now - Number(await $.store.get(LAST_AT)) < HOUR) return
      await $.store.set(LAST_AT, now)
      await $.ui.open({ id: PANE, title: '☕ Break' })
      $.ui.toast('☕ Cozy break time: water and a stretch.')
    })

    return next(e)
  })

  on('command.run', { command: 'break' }, async $ => {
    await $.ui.open({ id: PANE, title: '☕ Break' })

    return { text: 'Break reminder opened.' }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button } = $.ui.resolve(e)

    return (
      <Box flexDirection="column" gap={1} padding={1}>
        <Text bold color={WARM}>
          Time to stretch 🧘 and drink water 💧
        </Text>
        <Button key="done" onPress={() => $.ui.close({ id: PANE })}>
          ✨ Done, back to it
        </Button>
      </Box>
    )
  })
}
