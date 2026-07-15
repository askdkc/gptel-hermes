---
requires_tools: [obsidian]
name: obsidian
description: Read, search, create, and edit notes in an Obsidian vault.
platforms: [linux, macos, windows]
---

# Obsidian Vault

Use the external `obsidian` capability for vault operations. It must resolve a
configured vault and accept note paths relative to that vault. This Skill does
not assume that a vault is inside the current workspace.

## Vault resolution

Resolve the active vault through the `obsidian` integration before operating on
notes. A configuration such as `OBSIDIAN_VAULT_PATH` may identify the vault for
that integration, but do not pass the variable text itself as a path. Do not
turn it into a workspace-relative path by guessing, and do not use the standard
workspace file tools for an outside vault.

If no vault is configured or the external capability is unavailable, stop and
report that the vault cannot be accessed. The fallback `~/Documents/Obsidian
Vault` is only a human configuration suggestion, not an access guarantee.

## Read and search

- Read notes through `obsidian`, using paths relative to the resolved vault.
- List markdown notes through the integration's file-list operation.
- Search note contents through its content-search operation, restricted to
  `*.md` when appropriate.
- Prefer the integration's structured results so note names and locations are
  not confused with shell output.

## Create and edit

- Create a note through the integration's write operation with the full
  markdown content.
- For a focused edit, use its anchored patch operation after reading the note.
- For a simple append, use its append operation or rewrite the complete note
  when that is safer.
- Preserve YAML frontmatter, existing wikilinks, and unrelated content.

## Wikilinks

Obsidian links notes with `[[Note Name]]` syntax. When creating notes, use
wikilinks for related notes and verify that linked note names exist when the
integration can list them.

## Safety

- Never claim that a note changed until the integration reports success.
- Keep vault paths and note paths separate; a vault path identifies the
  external store, while a note path is relative to it.
- Do not silently fall back to a different vault.
- Do not perform bulk rewrites without an explicit user request.
