# gptel + native Emacs Lisp MVP

## API mapping

| gptel | Native implementation |
|---|---|
| `gptel-system-prompt` | Inject compact skill metadata and bounded MEMORY/USER snapshots once per buffer/session |
| `gptel-make-tool` | Register `hermes_skill_view` and confirmed `hermes_memory` tools |
| `gptel-pre-tool-call-functions` | Confirm or block side-effecting calls |
| `gptel-post-tool-call-functions` | Optional audit/progress hooks |
| `gptel-context` | Explicit file/buffer context, separate from persistent memory |

For a gptel-first integration, keep scanning, frontmatter extraction, path validation, prompt construction, and atomic memory writes in the same `gptel-hermes.el` package. Use `directory-files-recursively`, `with-temp-buffer`, and `rename-file` before introducing a subprocess bridge.

## Prompt and progressive disclosure

The initial prompt should contain only skill metadata plus bounded memory/profile snapshots. The selected full `SKILL.md` should appear only in the `hermes_skill_view` tool result, with a source reference such as `Source: skills/category/name/SKILL.md`.

`gptel-hermes-prompt-inspect` should expose the exact buffer-local system prompt. Enable should snapshot deliberately; a later memory write must not mutate the current `gptel-system-prompt`, preserving provider prefix caching.

## Reproduction recipe

1. Bind `gptel-hermes-home` to a temporary fixture.
2. Create `skills/category/demo/SKILL.md`, `memories/MEMORY.md`, and `memories/USER.md`.
3. Assert the prompt contains `name`, `description`, memory, and profile but not the full skill body.
4. Call the registered `hermes_skill_view` function; assert the full body and source reference are returned.
5. Exercise `hermes_memory` add/replace/remove; assert persistence, duplicate rejection, size limits, and atomic replacement.
6. Try `skill ../secret`, absolute paths, and symlink escapes; each must fail before an unsafe file is opened.
7. Exclude `.archive`, `.hub`, `.git`, `.github`, `references`, `templates`, `assets`, and `scripts` from the active index.
8. Byte-compile the package and run the ERT suite against the checked-out gptel source.

## Compatibility details

Use the actual gptel tool schema: argument `:type` values are symbols such as `string`, enum values are vectors, and `:include t` keeps the tool call/result available as model-facing context.

## Known ceiling

Session FTS search, terminal/file mutation, delegation, and background review remain separate follow-on capabilities. Do not claim Hermes feature parity until each has a defined native implementation and isolated verification.

If an external runtime is still chosen, measure cold-start cost before claiming it is faster; a source-script process per tool call can dominate the actual file work. Prefer a resident service only when the measurement justifies the added complexity.
