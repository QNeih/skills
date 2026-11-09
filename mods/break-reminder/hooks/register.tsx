import type { Register } from 'claude-code'

const PANE = 'break-reminder'
const HOUR = 60 * 60 * 1000

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'break',
      description: 'Show the drink-and-stretch reminder now',
    })
    $.clock.every(HOUR, async () => {
      await $.ui.open({ id: PANE, title: 'Break' })
      $.ui.toast('Time to drink some water and stretch.')
    })

    return next(e)
  })

  on('command.run', { command: 'break' }, async $ => {
    await $.ui.open({ id: PANE, title: 'Break' })

    return { text: 'Break reminder opened.' }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button } = $.ui.resolve(e)

    return (
      <Box flexDirection="column" gap={1}>
        <Text bold>Time for a break</Text>
        <Text>Drink a glass of water.</Text>
        <Text>Stand up and stretch for a minute.</Text>
        <Button key="done" onPress={() => $.ui.close({ id: PANE })}>
          Done
        </Button>
      </Box>
    )
  })
}
