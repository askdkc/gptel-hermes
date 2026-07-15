---
requires_tools: [hermes_terminal, hermes_terminal_authenticated]
name: claude-code
description: "Delegate bounded coding and review tasks to the Claude Code CLI."
version: 2.3.0
author: Hermes Agent + Teknium
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [Coding-Agent, Claude, Autonomous, Refactoring, Code-Review]
    related_skills: [codex, opencode, hermes-agent]
---

# Claude Code CLI

Use [Claude Code](https://code.claude.com/docs/en/cli-reference) for a bounded
coding, analysis, or review task in the current workspace. This bundled Skill
supports foreground, one-shot invocations only.

## Prerequisites

- The `claude` executable is installed and authenticated.
- The requested repository is the current workspace or a workspace-relative
  directory.
- The task has a clear scope and a bounded verification command.

Check readiness when needed:

```python
hermes_terminal_authenticated(program="claude", arguments=["--version"], cwd=".")
```

## One-shot coding task

Use print mode with a turn limit. Authenticated agent calls are source-editing
only: do not ask Claude to run project tests, builds, hooks, package scripts,
or other repository-controlled commands. Run verification later through the
sanitized terminal.

```python
hermes_terminal_authenticated(
    program="claude",
    arguments=["-p", "Add error handling to the API calls. Edit files only; leave all project command execution to the caller.", "--safe-mode", "--tools", "Read,Edit,Write", "--max-turns", "10"],
    cwd=".",
    timeout=300)
```

Use an explicit tool allowlist when the task does not need the full default
capability set:

```python
hermes_terminal_authenticated(
    program="claude",
    arguments=["-p", "Review src/auth.py for security issues.", "--safe-mode", "--tools", "Read", "--max-turns", "5"],
    cwd=".",
    timeout=300)
```

## Review task

Ask for a machine-readable result when a caller needs to parse the response:

```python
hermes_terminal_authenticated(
    program="sh",
    arguments=["-c", "set -eu; input=\"$(mktemp \"${TMPDIR:-/tmp}/gptel-hermes-review.XXXXXX\")\"; files=\"$(mktemp \"${TMPDIR:-/tmp}/gptel-hermes-review-files.XXXXXX\")\"; trap 'rm -f \"$input\" \"$files\"' EXIT HUP INT TERM; if git rev-parse --verify HEAD >/dev/null 2>&1; then git diff HEAD --no-ext-diff --unified=80 >\"$input\"; else git diff --cached --no-ext-diff --unified=80 >\"$input\"; git diff --no-ext-diff --unified=80 >>\"$input\"; fi; git ls-files -z --others --exclude-standard >\"$files\"; xargs -0 -n1 sh -c 'if [ \"$#\" -eq 0 ]; then exit 0; fi; status=0; git diff --no-index --no-ext-diff --unified=80 -- /dev/null \"$1\" >>\"$0\" || status=$?; [ \"${status:-0}\" -eq 1 ] || exit \"${status:-0}\"' \"$input\" <\"$files\"; claude -p 'Review the supplied unified diff and list high-risk changes.' --safe-mode --tools '' --output-format json --max-turns 3 <\"$input\""],
    cwd=".",
    timeout=300)
```

The producer writes the review input before invoking Claude. It uses
`git diff HEAD` for repositories with a commit. In an initial (unborn)
repository it appends both the cached diff and the working-tree diff, so a
file changed after staging is reviewed at its current content. It then appends
all non-ignored untracked files using NUL-safe `git ls-files -z` and
`git diff --no-index -- ...`. Any producer failure stops the command before
Claude runs; it is not hidden by a pipeline's exit status.

## Verification and handoff

After the command exits, inspect the reported files and run the project's
verification command in a separate `hermes_terminal` call. Use
`hermes_terminal_authenticated` only when verification explicitly requires
persistent user credentials or the real HOME, and never for untrusted
repository-controlled code. Report the command, exit result, changed files,
and any unresolved findings.

This Skill deliberately does not promise interactive TUI input, PTY control,
background execution, process polling, session continuation, tmux, or agent
teams. Those require an external integration that is not part of the standard
Hermes tool set.
