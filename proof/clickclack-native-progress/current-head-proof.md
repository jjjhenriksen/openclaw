# Current-head ClickClack native progress proof

- OpenClaw head: `fe7bd4eb3a` (`agent/clickclack-native-progress`, rebased onto upstream `origin/main` on 2026-07-31)
- ClickClack server: local dev server at `127.0.0.1:18082`
- Surface: `ClickClack PR Testing / #PR tests`
- Endpoint: `POST /api/realtime/ephemeral`
- Scope: a newly created local proof bot with `messages:write`; no credential is included here

## Observed request results

The live run sent ordered `agent.progress` frames for one turn:

1. `seq=1`, `op=append`, native `Agent is responding` line: HTTP `202`
2. `seq=2`, `op=append`, tool line `Current-head native progress`: HTTP `202`
3. `seq=3`, `op=clear`: HTTP `202`

The attached screenshot was captured between frames 2 and 3. The ClickClack UI visibly rendered both the native response row and the tool progress row. After frame 3, the yellow native progress row was gone; the clear request completed with `cleanup=complete`.
