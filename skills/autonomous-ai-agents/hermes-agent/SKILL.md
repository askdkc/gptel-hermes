---
requires_tools: [hermes_skill_view, hermes_terminal_authenticated]
name: hermes-agent
description: "Configure, extend, or contribute to Hermes Agent."
version: 2.3.0
author: Hermes Agent + Teknium
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [hermes, setup, configuration, multi-agent, cli, gateway, development]
    homepage: https://github.com/NousResearch/hermes-agent
    related_skills: [claude-code, codex, opencode]
---

# Hermes Agent

Use this Skill when configuring or contributing to
[Hermes Agent](https://github.com/NousResearch/hermes-agent), or when a user
needs a precise explanation of its CLI, configuration, skills, tools, memory,
or delegation features.

## Scope and prerequisites

- Verify that the `hermes` executable is installed and authenticated.
- Use the repository or configuration directory explicitly named by the user.
- Read the relevant upstream documentation before asserting version-specific
  behavior.
- Treat API keys, auth files, session data, and configuration as sensitive.

Check the local installation with a bounded foreground command:

```python
hermes_terminal_authenticated(program="hermes", arguments=["--version"], cwd=".")
```

## Configuration

Use the CLI's non-interactive commands when available:

```python
hermes_terminal_authenticated(program="hermes", arguments=["config", "get", "model.provider"], cwd=".")
hermes_terminal_authenticated(program="hermes", arguments=["tools", "list"], cwd=".")
```

For settings that require an editor or interactive wizard, tell the user the
exact command to run and the expected configuration change. Do not claim that
an interactive configuration step completed through a foreground one-shot
call.

Common configuration areas include model/provider credentials, agent turn
limits, terminal backend settings, memory, security, delegation, checkpoints,
and enabled toolsets. Confirm the installed version before relying on a key or
subcommand.

## Skills and tools

Use `hermes_skill_view` to inspect a skill's authoritative body before
describing or changing it. Keep a skill's metadata honest: hard dependencies
must be callable in the current environment, and optional integrations belong
in a separate explicitly external workflow.

Use the configured external `browser`, `session_search`, and `delegate_task`
capabilities only when the task actually needs them. Report unavailable
capabilities instead of substituting an unrelated tool.

## One-shot agent work

For a bounded independent task, run Hermes in query mode through
`hermes_terminal_authenticated` and keep the working directory explicit:

```python
hermes_terminal_authenticated(
    program="hermes",
    arguments=["chat", "-q", "Inspect the current repository and report the three highest-risk test gaps."],
    cwd=".",
    timeout=300)
```

For a short isolated subtask, use `delegate_task` when that external
integration is configured. Include the goal, relevant files, exact verification
command, and the requirement to report findings separately from edits.

## Safety boundaries

This bundled Skill documents foreground, bounded operations. It does not promise
interactive TUI input, PTY control, background jobs, session polling, or
long-running orchestration. Those require a separate external integration and
must not be represented as available standard Hermes tools.

Never expose secrets from configuration or auth files. Before changing a
gateway, plugin, toolset, or memory policy, show the intended setting and verify
the resulting configuration with a read-only command.

## Contribution workflow

1. Read the relevant source, tests, and current documentation.
2. Reproduce the reported behavior with a bounded command.
3. Make the smallest focused change.
4. Run the narrow test, then the full relevant suite.
5. Report files changed, commands run, results, and remaining uncertainty.
