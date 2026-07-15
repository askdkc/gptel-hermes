---
requires_tools: [hermes_skill_view, hermes_memory]
name: gptel-agent-integration
description: Integrate gptel with local agent capabilities such as skill indexes, persistent memory, tool calling, and language-runtime bridges while preserving prompt-cache stability and security boundaries.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [emacs, gptel, agent, skills, memory, tool-calling, common-lisp]
    related_skills: [my-ponytail, hermes-agent]
---

# gptel Agent Integration

## When to Use

Use this skill when extending gptel into an agentic frontend, especially when the implementation should expose a local skill catalog, persistent memory, or tools. Prefer keeping the small filesystem/prompt layer inside Emacs Lisp when gptel is already the frontend.

## Architecture

Prefer a thin gptel companion package over a fork of gptel:

```text
gptel buffer
  -> stable system prompt: skill metadata + memory snapshot
  -> model tool call: hermes_skill_view / hermes_memory / safe tools
  -> native Elisp implementation or a deliberately chosen external runtime
  -> tool result back to gptel
```

Use gptel's native extension points first:

- `gptel-system-prompt` for stable, buffer-local instructions and metadata.
- `gptel-make-tool` for model-visible tools.
- `gptel-pre-tool-call-functions` for confirmation and policy gates.
- `gptel-post-tool-call-functions` for logging or state updates.
- `gptel-context` only for explicit user-selected files/buffers, not as a substitute for a skill index.
- MCP when a mature external tool server already exists.

## Skill Loading

Implement progressive disclosure:

1. Scan skill directories and expose only `name`, `description`, and category in the system prompt.
2. Provide a `hermes_skill_view` tool that loads the complete `SKILL.md` only when the model selects it.
3. Load referenced files on demand rather than injecting every `references/` file.
4. Treat slash commands as an optional deterministic fast path; natural-language routing should use the model over the compact catalog.

The directory tree is organizational metadata, not a deterministic semantic router. Do not pretend that a category path alone selects the correct skill.

## Memory Loading

Keep persistent memory separate from skills:

- `MEMORY.md`: environment facts, project conventions, technical lessons.
- `USER.md`: user preferences, communication style, and stable workflow expectations.
- Conversation history is not searchable through a package-standard tool; use the current conversation and explicit files instead.

Load a bounded memory snapshot at session start. Do not mutate the current system prompt after a memory write; persist the write immediately, but make the updated snapshot visible on the next session or through the live tool result. This preserves provider prefix caching.

Memory writes must retain validation, size limits, duplicate handling, atomic persistence, and prompt-injection scanning. If a mature existing runtime already provides these guarantees, reuse it; otherwise implement the smallest equivalent in native Elisp rather than adding a process boundary solely for abstraction.

## Runtime Boundary

When gptel is the frontend and the required work is filesystem scanning, prompt construction, and small tools, prefer an **Emacs Lisp-only implementation**:

```text
gptel buffer -> gptel-hermes.el -> skills / MEMORY.md / USER.md
```

This keeps configuration and behavior in one Lisp runtime, removes process startup and quoting boundaries, and makes buffer-local prompt snapshots and gptel tool registration direct. Use `directory-files-recursively`, `with-temp-buffer`, `rename-file`, and gptel's native APIs before adding a bridge process.

Use an external runtime only when it buys something concrete: a long-running service, an existing library, FFI, or heavyweight processing. If using Common Lisp or another runtime, do not invoke a source script per tool call merely for theoretical speed; measure cold-start cost first, and daemonize only when the measurement justifies it. A bridge should remain narrow and command-oriented, and its `prompt-inspect` output is the acceptance oracle for what the model actually receives.

For a first milestone, implement and verify the read path before side effects. Once stable, add memory add/replace/remove with explicit confirmation; keep terminal execution, session search, delegation, and background review as separate follow-on capabilities.

When scanning a Hermes-compatible skills root, exclude `.archive`, `.hub`, `.git`, `.github`, and support directories such as `references`, `templates`, `assets`, and `scripts` from the active catalog. These contain historical or linked material, not necessarily active top-level skills.

## Security and Compatibility

- Reject absolute paths, `..` traversal, and platform-specific drive paths at the bridge boundary.
- Do not expose write or shell tools without explicit confirmation policy.
- Avoid injecting full skill bodies into every request.
- Preserve a stable system prompt for the life of a gptel conversation.
- Validate the bridge in an isolated fixture before pointing it at a real profile.
- Check the selected backend/model's tool-calling support; do not assume every backend handles tools identically.
- If Emacs is unavailable, report that Elisp byte-compilation was not run rather than claiming it passed.

## Verification

Minimum checks for a native gptel integration:

1. Byte-compile the Elisp package against the checked-out gptel source.
2. Run an isolated ERT fixture and assert skill `name`, `description`, and category appear in the prompt.
3. Assert the initial prompt contains memory/profile but not the full skill body.
4. Call the registered `hermes_skill_view` tool and assert the full body plus source reference are returned.
5. Exercise memory add/replace/remove and assert persistence, duplicate rejection, limits, and atomic replacement.
6. Verify traversal inputs such as `../secret` fail.

## Pitfalls

- Do not choose an external runtime by default when gptel already owns the configuration and execution environment; a source-script process per tool call can be slower and less coherent than native Elisp.
- Do not reimplement the full agent core in Elisp just because gptel can execute Elisp tools.
- Do not route natural-language requests with a category-name lookup; provide the catalog and let the model select `hermes_skill_view`.
- Do not make memory writes modify `gptel-system-prompt` mid-session.
- Do not start with terminal, delegation, cron, or background review before the read path is verified.
- Do not claim the integration is complete when only the read-only MVP exists; list skipped capabilities explicitly.

## Supporting Reference

See `references/gptel-hermes-mvp.md` for the compact native-Elisp API mapping and verification recipe.
