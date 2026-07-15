---
requires_tools: [hermes_terminal, hermes_terminal_authenticated]
name: codex
description: "Delegate bounded coding and review tasks to the Codex CLI."
version: 1.1.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [Coding-Agent, Codex, Autonomous, Refactoring, Code-Review]
    related_skills: [claude-code, opencode, hermes-agent]
---

# Codex CLI

Use [Codex](https://github.com/openai/codex) for a bounded coding or review task
in the current workspace. This bundled Skill supports foreground, one-shot
invocations only.

## Prerequisites

- The `codex` executable is installed and authenticated.
- The requested repository is the current workspace or a workspace-relative
  directory.
- The task has a clear scope and a bounded verification command.

Check readiness when needed:

```python
hermes_terminal_authenticated(program="codex", arguments=["--version"], cwd=".")
```

## One-shot coding task

Pass the complete task as one prompt and keep the working directory explicit.
Authenticated agent calls are source-editing only: do not ask Codex to run
project tests, builds, hooks, package scripts, or other repository-controlled
commands. Run verification later through the sanitized terminal.

```python
hermes_terminal_authenticated(
    program="codex",
    arguments=["exec", "Add dark mode to the settings screen. Edit files only; leave all project command execution to the caller."],
    cwd=".",
    timeout=300)
```

## Review task

Ask Codex to inspect the current diff and return findings without changing the
workspace:

```python
hermes_terminal_authenticated(
    program="codex",
    arguments=["exec", "review", "--uncommitted"],
    cwd=".",
    timeout=300)
```

## Verification and handoff

After the command exits, inspect the reported files and run the project's
verification command in a separate `hermes_terminal` call. Use
`hermes_terminal_authenticated` only when verification explicitly requires
persistent user credentials or the real HOME, and never for untrusted
repository-controlled code. Report the command, exit result, changed files,
and any unresolved findings.

This Skill deliberately does not promise interactive TUI input, PTY control,
background execution, process polling, or session continuation. Those require
an external integration that is not part of the standard Hermes tool set.
