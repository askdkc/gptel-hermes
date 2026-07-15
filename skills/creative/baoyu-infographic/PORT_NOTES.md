# Port Notes — baoyu-infographic

Ported from [JimLiu/baoyu-skills](https://github.com/JimLiu/baoyu-skills) v1.56.1.

## Changes from upstream

The 45 upstream reference files remain verbatim copies; `SKILL.md` carries the
Hermes-specific adaptations documented below.

### SKILL.md adaptations

| Change | Upstream | Hermes |
|--------|----------|--------|
| Metadata namespace | `openclaw` | `hermes` |
| Trigger | `/baoyu-infographic` slash command | Natural language skill matching |
| User config | EXTEND.md file (project/user/XDG paths) | Removed — not part of Hermes infra |
| User prompts | `AskUserQuestion` (batched) | Ask in the conversation, one question at a time |
| Image generation | baoyu-imagine (Bun/TypeScript) | `image_gen` tool |
| Platform support | Linux/macOS/Windows/WSL/PowerShell | Linux/macOS only |
| File operations | Bash commands | Hermes file tools (hermes_file_write, hermes_file_read) |

### What was preserved

- All layout definitions (21 files)
- All style definitions (21 files)
- Core reference files (analysis-framework, base-prompt, structured-content-template)
- Recommended combinations table
- Keyword shortcuts table
- Core principles and workflow structure
- Author, version, homepage attribution

## Syncing with upstream

To pull upstream updates:
```bash
# Compare versions
curl -sL https://raw.githubusercontent.com/JimLiu/baoyu-skills/main/skills/baoyu-infographic/SKILL.md | head -5
# Look for version: line

# Diff reference files
diff <(curl -sL https://raw.githubusercontent.com/.../references/layouts/bento-grid.md) references/layouts/bento-grid.md
```

Reference files can be overwritten directly (they're unchanged from upstream). SKILL.md must be manually merged since it contains Hermes-specific adaptations.
