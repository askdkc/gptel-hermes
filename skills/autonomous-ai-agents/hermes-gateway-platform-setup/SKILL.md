---
requires_tools: [hermes_terminal_authenticated]
name: hermes-gateway-platform-setup
description: "Set up and troubleshoot Hermes messaging gateway platform plugins (Telegram, Slack, WhatsApp, Photon/iMessage, etc.) with verification-first CLI workflows."
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [hermes, gateway, messaging, plugins, setup, troubleshooting]
    related_skills: [hermes-agent]
---

# Hermes Gateway Platform Setup

Use this skill when the user asks to add, configure, enable, troubleshoot, or verify a Hermes messaging platform such as Telegram, Slack, WhatsApp, Photon/iMessage, Signal, Matrix, Teams, LINE, Email, SMS, or another gateway adapter.

This skill supplements the protected bundled `hermes-agent` skill. Treat official docs and the live CLI as source of truth, but use the workflow below to avoid common plugin-registration and setup pitfalls.

Run the Hermes commands below through `hermes_terminal_authenticated`. Gateway
configuration and plugin state live under the user's real `~/.hermes` home;
the standard terminal's temporary home cannot provide a durable setup. Complete
interactive login or device approval outside the tool because terminal stdin is
closed.

## Operating rules

1. Load `hermes-agent` first for authoritative Hermes command context.
2. Verify the live CLI and installed version before assuming a documented subcommand exists:
   - `hermes --version`
   - `hermes gateway --help`
   - `hermes plugins list`
3. For platform plugins, check whether the adapter is bundled but disabled. Many platform adapters are opt-in plugins.
4. If a plugin must be enabled, run:
   - `hermes plugins enable <plugin-key>`
5. After enabling a plugin, remember that new CLI commands may require a fresh Hermes process/session before appearing. Do not conclude the platform is unsupported just because `hermes <platform>` is still absent in the same long-running session.
6. Prefer setup through the supported surface:
   - `hermes gateway setup` for the unified wizard
   - platform-specific setup command if it is registered in the current CLI
7. Verify configuration without revealing secrets:
   - platform `status` command when available
   - `hermes gateway status`
   - logs only for errors, with secrets redacted
8. For production-like gateway changes, inspect read-only first, state risk, and ask before destructive edits. Enabling a plugin or writing credentials affects the active Hermes profile.

## Plugin CLI registration pitfall

A bundled plugin can appear in `hermes plugins list` and be enabled in `~/.hermes/config.yaml`, while its top-level CLI command is not available until a new Hermes CLI process imports the enabled plugin registry.

If `hermes plugins enable platforms/<name>` reports success but `hermes <name> ...` still says `invalid choice`, do not repeat the same command endlessly. Use one of these safer next steps:

- Start a fresh terminal/Hermes session and retry the command.
- Try the unified wizard: `hermes gateway setup`.
- If you are operating inside the Hermes source checkout and must continue in the same session, inspect the plugin's `cli.py` and invoke its registered argparse entry point using the Hermes venv Python only as a temporary diagnostic workaround.

Do not save a durable negative rule like "the plugin command does not work"; the durable lesson is that plugin command registration is process-start sensitive.

## Photon/iMessage notes

Photon/iMessage is a gateway platform plugin, usually keyed as `platforms/photon` / `photon-platform` in plugin listings. Setup normally performs device login, project/secret provisioning, phone registration, assigned iMessage line display, and Node sidecar dependency installation.

Expected user-facing flow:

```bash
hermes plugins enable photon-platform       # or platforms/photon, depending on CLI accepted key
# restart/new Hermes process if the photon subcommand is not registered yet
hermes photon setup --phone +15551234567
hermes photon status
hermes gateway start
```

If the platform command is unavailable immediately after enabling, see `references/photon-plugin-cli.md` for a concise diagnostic workaround and what to verify.

## Verification checklist

Before telling the user setup succeeded, verify at least one concrete signal:

- plugin is enabled in `hermes plugins list` or config
- required credentials are present according to the platform status command
- sidecar/dependency checks pass when the platform uses a sidecar
- `hermes gateway status` shows the gateway running or ready
- a real inbound/outbound test message succeeds, when credentials and user approval are available

If blocked by user action such as OAuth/device approval or entering a phone number, stop and give exactly the URL/code/input requested, then wait for the user to confirm completion.
