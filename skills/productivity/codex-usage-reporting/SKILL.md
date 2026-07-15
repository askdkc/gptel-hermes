---
requires_tools: [hermes_terminal_authenticated]
name: codex-usage-reporting
description: Report current OpenAI Codex usage in the user's exact compact format.
version: 1.1.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [codex, usage, quota, reset, timezone]
---

# Codex Usage Reporting

## Trigger

Use whenever the user asks for Codex usage, utilization, quota, allowance, or `usage?`.

Run `codex-usage` through `hermes_terminal_authenticated` so its local Codex
authentication and configuration are visible. Do not run interactive login from
the tool; the user must authenticate separately.

## Procedure

1. Run `codex-usage` every time. Never reuse a previous result.
2. Treat the current Codex usage model as a single **Weekly** limit. Do not report the retired `5hr` or `All` windows.
3. Report used percentage, not remaining percentage:

   `Weekly: X% used`
   `reset: M/D HH:MM JST`

   `reset credit: N`

4. Convert reset timestamps to JST (`Asia/Tokyo`) and use compact `M/D HH:MM JST` formatting.
5. If the command does not return a value, report `—`; never infer or invent it.
6. Keep the output compact. Do not explain billing or pricing unless asked.

## Verification

- Confirm `codex-usage` exited successfully.
- Preserve the distinction between a used percentage and a remaining percentage.
- Never report UTC as JST.
- If Codex's `/status` reports only `Weekly limit`, treat that as authoritative and do not recreate a 5-hour limit.

- Distinguish the short 5-hour window from the all/weekly window.
- Never report remaining percentage as used percentage.
- Never report UTC as JST.
