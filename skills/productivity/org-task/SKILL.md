---
name: org-task
description: Manage tasks whose source of truth is the current Emacs Org agenda, including agenda-aware readouts, custom TODO states, confirmed state changes, and Org capture. Use when reviewing, updating, or capturing tasks in Org files through gptel-hermes.
---

# Org Task Management

Use the Org files configured by Emacs as the task database. Keep task
discovery, stale-target checks, state changes, and capture operations inside
the dedicated gptel-hermes Org tools.

## Required workflow

1. Call `hermes_org_agenda` before proposing or applying a task change.
2. Use `view: "open"` for unfinished work, `view: "all"` for a complete
   review, and `view: "tag"` with an exact `YYYYMM` tag for a monthly review.
3. Treat the returned absolute file, one-based line, exact heading, state,
   tags, priority, and planning timestamps as the current target snapshot.
4. Call `hermes_org_task` for one operation only after the target and intended
   result are clear. Let its confirmation policy gate every write.
5. Re-read the agenda after a write when the result needs verification.

## Scope and configuration

- Read only files resolved from `org-agenda-files`. Do not scan `~/org`, the
  home directory, or arbitrary files with terminal or generic file tools.
- Resolve `org-agenda-files` on every tool call; do not cache its value.
- If it is empty, report that the Org task scope is unconfigured. Do not infer
  a directory. An explicit fallback may be enabled by the user with:

  ```elisp
  (setq gptel-hermes-org-directory-fallback t)
  ```

  This uses the configured `org-directory` only when `org-agenda-files` is
  empty. A directory path may also be assigned explicitly to
  `gptel-hermes-org-directory-fallback`.
- Do not write a file merely because it is in `org-directory`; it must be in
  the resolved agenda scope.

## TODO states

Use the TODO and DONE keywords returned by the current Org buffer and Emacs
configuration. Do not hard-code or overwrite `org-todo-keywords`.

Configurations may define states such as `TODO`, `DOIN`, `WAIT`, `TRET`,
`REMD`, `DONE`, and `SKIP`; treat those names as examples, not as a required
global vocabulary. Pass the exact current keyword to `hermes_org_task`.

For a state change, provide the latest agenda result's `file`, `line`, and
exact `heading`, plus the desired current `keyword`. Never guess a line after
the file has changed. Change one task per call. Change to `DONE` or `SKIP`
only when the user has confirmed completion or the execution result provides
that confirmation.

## Capture

Use `hermes_org_task` with `action: "capture"`, the requested text, and an
existing `org-capture-templates` key. Do not choose a destination file or
create a template in this skill. If no template is configured, explain that
the user must configure it first; if a key is missing, use the returned list
of available keys.

A minimal user configuration can look like this (the target file must also
be in `org-agenda-files`):

```elisp
(setq org-capture-templates
      '(("t" "Task" entry
         (file+headline "work.org" "Tasks")
         "* TODO %?")))
```

Do not duplicate events already represented in Google Calendar or another
calendar system in Org. Record an Org task only when it is a task rather than
an already-synchronized appointment.

## Boundaries

Do not edit `SKILL.md` or Org files directly. Do not use generic terminal or
file tools to bypass the Org tools. This skill does not provide background
monitoring, notifications, cron, launchd jobs, or synchronization with
Google Calendar, Slack, Backlog, or other external systems.
