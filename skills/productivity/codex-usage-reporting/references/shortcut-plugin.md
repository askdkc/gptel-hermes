# Codex usage command integration

The user requested deterministic shortcuts because repeated free-form `usage?` requests caused format drift. A user-local Hermes plugin registers `/cu` and `/codex-usage`, invokes the local `codex-usage` executable directly, converts reset timestamps to JST, and emits the compact block:

```text
5hr: X% used
reset: M/D HH:MM JST

All: X% used
reset: M/D HH:MM JST

reset credit: N
```

The plugin must never infer a missing window: use `—`. It is enabled in the active profile and takes effect after a new session or gateway restart.
