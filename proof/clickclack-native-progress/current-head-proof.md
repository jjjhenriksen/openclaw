# Exact-current-head ClickClack native progress proof

- OpenClaw PR: [#116683](https://github.com/openclaw/openclaw/pull/116683)
- Behavior-bearing OpenClaw head: `63156dee3777d58317feff587ef25eec04ab0709`
- ClickClack server: local dev server at `127.0.0.1:18082`
- Surface: `ClickClack PR Testing / #PR tests`
- Endpoint: `POST /api/realtime/ephemeral`
- Scope: a newly created local proof bot with `messages:read,messages:write`; no credential is included here

The run imported the `progress.ts` and `http-client.ts` modules from the exact PR head, used the real ClickClack REST endpoint, and opened the real ClickClack browser surface. The proof bot token was scoped to this workspace and is not included in the artifact.

## Observed request results

The live run sent ordered `agent.progress` frames for turn `proof-63156dee`:

1. `seq=1`, `op=append`, native `Agent is responding` line: HTTP `202`
2. `seq=2`, `op=append`, tool line `Exact-current-head native progress`: HTTP `202`
3. `seq=3`, `op=clear`: HTTP `202`

The browser contained one matching progress line while the turn was active and zero after `finalize()` completed. The attached screenshot was captured while both native progress rows were visible.

## Final delivery

After cleanup, the same current-head ClickClack client sent:

```text
Exact-current-head final reply 63156dee
```

- final message ID: `msg_01kywdfgb28b95g3b0agj7e6ff`
- browser-visible final text: confirmed
- API channel listing: persisted: confirmed
- API message read-back: confirmed
- browser console errors/warnings: none

The final message remained visible after the progress clear, demonstrating that transient progress cleanup did not suppress final delivery.
