---
requires_tools: [hermes_terminal]
name: svelte-ai-tools
description: Use when working on Svelte frontend tasks, especially creating or editing .svelte files, SvelteKit code, or Svelte 5 runes code where the official Svelte AI tools/MCP/docs should be used for current framework-specific guidance.
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [svelte, sveltekit, frontend, mcp, ai-tools]
    related_skills: []
---

# Svelte AI Tools

## Overview

The user frequently uses Svelte for frontend work. For Svelte tasks, prefer the official Svelte AI tools repository as current framework-specific context:

- Repository: `https://github.com/sveltejs/ai-tools`
- Package/MCP server: `@sveltejs/mcp`
- Purpose: official Svelte MCP server, skills, prompts, resources, and plugins for helping agents write correct Svelte/SvelteKit/Svelte 5 code.

## When to Use

Use this skill for:

- Creating or editing `.svelte` files
- SvelteKit routing/load/action/form work
- Svelte 5 runes code such as `$state`, `$derived`, `$effect`
- Svelte component review/debugging
- Agent setup for Svelte-aware coding tools
- Svelte + Inertia/Laravel frontend work when Svelte-specific behavior matters

Do not use this as a substitute for inspecting the actual project files. Always verify the app's installed Svelte/SvelteKit versions and local conventions first.

## Required Inspection

Before recommending Svelte-specific code, inspect project state when available:

```sh
node -p "require('./package.json').dependencies"
node -p "require('./package.json').devDependencies"
```

Prefer exact files. Use available file-search tools to inspect `src/**/*.svelte`, `+page.*`, and `+layout.*` files.

## Official Tooling

For MCP-capable clients, the local Svelte MCP server can be run with:

```sh
npx -y @sveltejs/mcp
```

For Codex CLI, the Svelte repository is also a plugin marketplace:

```sh
codex plugin marketplace add sveltejs/ai-tools
```

Manual Codex MCP config in the user's Codex configuration file:

```toml
[mcp_servers.svelte]
command = "npx"
args = ["-y", "@sveltejs/mcp"]
```

## MCP Capabilities to Prefer

When available, prefer Svelte MCP tools/resources for:

- `list-sections`: discover current documentation sections
- `get-documentation`: fetch current official Svelte docs sections
- `svelte-autofixer`: static-analysis suggestions for generated Svelte code
- `playground-link`: generate an ephemeral Svelte playground link for quick isolated examples

## Procedure

1. Identify the project's Svelte/SvelteKit versions and whether it uses Svelte 5 runes.
   Completion: package versions and relevant config files are known.
2. Inspect nearby project code before generating patterns.
   Completion: local naming, stores/runes usage, routing style, and formatting are known.
3. Use official docs/MCP context for uncertain Svelte behavior instead of guessing.
   Completion: claim is grounded in current docs or explicitly marked uncertain.
4. Generate the smallest applicable code change.
   Completion: code matches local conventions and compiles conceptually against project versions.
5. Verify with project commands when available.
   Completion: relevant check/build/test command was run or blocker is stated.

## Verification

Prefer project-native commands:

```sh
npm run check
npm run lint
npm run test
npm run build
```

For pnpm projects:

```sh
pnpm check
pnpm lint
pnpm test
pnpm build
```

## Common Pitfalls

1. **Assuming Svelte 5 syntax in older projects.** Verify versions first.
2. **Using generic web-component patterns.** Prefer Svelte idioms and local conventions.
3. **Skipping static analysis.** If MCP is available, run `svelte-autofixer` or equivalent project checks.
4. **Overwriting local state-management style.** Preserve existing runes/stores/context patterns unless the task is explicitly a migration.
5. **Treating playground examples as production-ready.** Playground links are useful for isolated reproduction, not proof of app integration.

## Rollback / No-op Path

If the project version or setup is unclear, do not perform broad rewrites. Provide a narrow patch or ask for the relevant `package.json`, component, and failing output.
