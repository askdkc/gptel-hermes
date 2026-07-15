---
requires_tools: [hermes_terminal, hermes_terminal_authenticated]
name: opencode
description: "Delegate bounded coding and review tasks to the OpenCode CLI."
version: 1.2.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [Coding-Agent, OpenCode, Autonomous, Refactoring, Code-Review]
    related_skills: [claude-code, codex, hermes-agent]
---

# OpenCode CLI

Use [OpenCode](https://opencode.ai) for a bounded coding or review task in the
current workspace. This bundled Skill supports foreground, one-shot
invocations only.

## Prerequisites

- The `opencode` executable is installed and authenticated with a provider.
- The requested repository is the current workspace or a workspace-relative
  directory.
- The task has a clear scope and a bounded verification command.

Check readiness when needed:

```python
hermes_terminal_authenticated(program="opencode", arguments=["--version"], cwd=".")
```

## One-shot coding task

Use `opencode run` and keep the working directory explicit. Authenticated
agent calls are source-editing only: do not ask OpenCode to run project tests,
builds, hooks, package scripts, or other repository-controlled commands. Run
verification later through the sanitized terminal.

```python
hermes_terminal_authenticated(
    program="opencode",
    arguments=["run", "Add retry logic to the API calls. Edit files only; leave all project command execution to the caller.", "--pure"],
    cwd=".",
    timeout=300)
```

Attach workspace-relative files when focused context is useful:

```python
hermes_terminal_authenticated(
    program="opencode",
    arguments=["run", "Review this configuration for security issues.", "-f", "config.yaml", "-f", ".env.example"],
    cwd=".",
    timeout=300)
```

Select a model only when the user or project configuration requires it:

```python
hermes_terminal_authenticated(
    program="opencode",
    arguments=["run", "Refactor the auth module. Edit files only; leave all project command execution to the caller.", "--model", "provider/model", "--pure"],
    cwd=".",
    timeout=300)
```

## Review and verification

For a review, ask OpenCode to inspect the current diff and report findings.
After the command exits, inspect the reported files and run the project's
verification command in a separate `hermes_terminal` call. Use
`hermes_terminal_authenticated` only when verification explicitly requires
persistent user credentials or the real HOME, and never for untrusted
repository-controlled code. Report the command, exit result, changed files,
and any unresolved findings.

This Skill deliberately does not promise interactive TUI input, PTY control,
background execution, process polling, or session continuation. Those require
an external integration that is not part of the standard Hermes tool set.
