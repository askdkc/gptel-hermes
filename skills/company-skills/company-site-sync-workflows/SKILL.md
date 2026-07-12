---
name: company-site-sync-workflows
description: Use for recurring company website update/sync/deploy tasks where the user refers to a site by short name. Look up the site-specific reference, run the exact recorded workflow, and report real command output succinctly.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [company-workflow, website, deploy, sync, git]
    related_skills: []
---

# Company Site Sync Workflows

## Overview

This class-level skill covers small recurring website update/sync workflows for company-managed sites. These tasks typically combine a Git update in a known checkout with a site-specific sync/deploy script.

Use this instead of creating one narrow skill per site. Store site-specific commands and paths in `references/<site>.md`.

## When to Use

Use when the user says things like:

- `<site>を更新して`
- `<site>更新`
- `<site>をpullしてsyncして`
- asks to run a remembered website update/deploy/sync workflow by short site name

Known references:

- `references/maedaweb.md` — maedaweb Git pull + sync script workflow

## Procedure

1. Identify the site short name from the user's request.
2. Read the matching `references/<site>.md` if available.
3. Run the exact workflow from the reference, including the recorded working directory.
4. Use a chained command when appropriate so later deploy/sync steps do not run after a failed prerequisite, e.g. `pwd && git pull && <sync-script>`.
5. Do not rely on shell state from previous turns; always set `workdir` explicitly.
6. Report only real command output and the actual exit status.

## Reporting

Keep the reply short and operational. Include:

1. Whether the Git update changed anything or was already up to date.
2. Whether the sync/deploy script exited successfully.
3. Key output lines, especially transfer/sync summaries.

## Pitfalls

- **Wrong directory risk:** Always use the site-specific working directory from the reference.
- **False success risk:** Do not say the site was updated unless the command was actually run and exited successfully.
- **Partial deploy risk:** Prefer a chained command that stops on failure rather than separate commands unless debugging.
- **Scope creep:** If the user asks for a new site workflow, capture the site-specific details in `references/<site>.md` under this umbrella rather than creating another narrow one-off skill.
- **Legacy/narrow skill overlap:** If session history mentions an older site-specific skill such as `maedaweb-update`, prefer this class-level `company-site-sync-workflows` skill and its reference file instead of reviving or duplicating the narrow skill.

## Verification Checklist

- [ ] Site-specific reference was used.
- [ ] Command ran with the recorded `workdir`.
- [ ] Git output is included or summarized.
- [ ] Sync/deploy command completed with exit code `0`.
- [ ] Final reply is in Japanese unless the user requested otherwise.
