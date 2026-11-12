import type { EngineInterface, Register } from 'claude-code'

type Row = { sessionId: string; title?: string; name?: string; link?: string; startedBy?: string; isRunning?: boolean; isArchived?: boolean }
type Family = { parent?: Row; kids: Row[] }

const SERVER = 'ccd_session_mgmt'

async function callJson($: EngineInterface, tool: string, args: Record<string, unknown>): Promise<unknown> {
  const r = await $.mcp.call(SERVER, tool, args)
  const block = r.content[0]
  const text = (block && block.type === 'text' ? block.text : undefined) ?? ''
  if (r.isError) throw new Error(`${tool}: ${text}`)
  // list_sessions answers plain text, not JSON, when the family is empty
  return text.startsWith('{') || text.startsWith('[') ? JSON.parse(text) : null
}

const label = (r: Row) => r.name ?? r.title ?? r.sessionId
const RUNNING = '#3fb950' // working
const WAITING = '#d29922' // idle, not archived: waiting on Quinn
const dot = (r: Row) => (r.isRunning ? RUNNING : WAITING)

let family: Family = { kids: [] }

async function refresh($: EngineInterface) {
  const self = (await callJson($, 'get_session', { session_id: 'self' })) as Row & { parentSessionId?: string; detached?: boolean }
  const rows = ((await callJson($, 'list_sessions', { linked: true, include_archived: true })) ?? []) as Row[]
  const parentId = self.detached ? undefined : self.parentSessionId
  family = {
    parent: parentId ? rows.find(r => r.sessionId === parentId) ?? { sessionId: parentId } : undefined,
    // Archived = done: drop it. include_archived stays so an archived parent still resolves.
    kids: rows.filter(r => r.startedBy === self.sessionId && !r.isArchived),
  }
  $.ui.invalidate('ui.render')
}

export const register: Register = on => {
  // Kids appear mid-session (start_session), so re-read after every turn.
  on('session.start', async ($, e, next) => {
    const result = await next(e)
    // ccd_session_mgmt is not connected yet at session.start, so read every second until
    // the first read lands (the back link shows then, before the first reply), then every 10s.
    // Kids change status while this session sits idle.
    // ponytail: 10s poll, two local MCP calls; a session-status event would replace it if the engine adds one.
    let ready = false
    let ticks = 0
    $.clock.every(1_000, () => {
      if (ready && ++ticks % 10) return
      refresh($).then(
        () => { ready = true },
        err => { if (!String(err).includes('no connected MCP tool')) throw err },
      )
    })
    return result
  })

  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    if (e.agentId === undefined) await refresh($)
    return result
  })

  on('ui.render', { component: 'AbovePrompt' }, ($, e, next) => {
    const { parent, kids } = family
    if (e.props.hasSurvey || (!parent && kids.length === 0)) return next(e)

    // Desktop draws a Link plain unless it is https:, so claude:// links go through `open`.
    const { Box, Text, Button } = $.ui.resolve(e)
    const open = (r: Row) => () => { void $.process.run(['open', r.link!]) }

    return (
      <Box flexDirection="row" justifyContent="space-between" width="100%">
        <Box>{parent?.link ? <Button key={parent.sessionId} label={`← ${label(parent)}`} onPress={open(parent)} /> : null}</Box>
        <Box gap={1}>
          {kids.filter(k => k.link).map(k => (
            <Button key={k.sessionId} onPress={open(k)}>
              <Text color={dot(k)}>●</Text> {label(k)}
            </Button>
          ))}
        </Box>
      </Box>
    )
  })
}
