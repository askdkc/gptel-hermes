---
requires_tools: [hermes_file_read, hermes_apply_patch, hermes_terminal]
name: groonga-full-text-debugging
description: Diagnose and fix Groonga/PGroonga false positives, false negatives, token-boundary errors, and chained-normalizer metadata loss with reproducible token streams and verified source patches.
version: 1.0.0
platforms: [linux, macos]
metadata:
  hermes:
    tags: [groonga, pgroonga, normalizer, tokenizer, full-text-search, debugging]
---

# Groonga Full-Text Debugging

Use this skill when Groonga or PGroonga returns surprising matches, especially after schema, materialized-view, aggregation, tokenizer, or normalizer changes.

## Working principles

- Separate **data-shape changes** from **tokenizer/normalizer behavior changes**.
- Inspect the actual token stream before inferring behavior from search results.
- Compare one variable at a time: normalizer chain, tokenizer option, delimiter, source row shape, or index definition.
- Treat `types`, `checks`, and `offsets` as pipeline metadata. A later normalizer may preserve normalized text while silently discarding boundary/source metadata.
- For source fixes, write the regression test first, observe the bad token or match, then build and run the narrowest relevant suite.

## Diagnosis workflow

1. Record Groonga version, tokenizer, all tokenizer options, normalizers in order, and index flags.
2. Minimize the input. Prefer diagnostic strings such as `abc def`, because a cross-boundary bigram like `cd` is obvious.
3. Compare a control with one normalizer against the full chain.
4. Run `table_tokenize ... --mode GET --output_pretty yes`; populate the lexicon/index first when GET mode would otherwise return no terms.
5. Run an end-to-end `select` proving the false positive or false negative, not only `normalize`.
6. Run `normalize ... WITH_TYPES|WITH_CHECKS` and, when available, source offsets. Locate where `GRN_CHAR_BLANK`, checks, or offsets disappear.
7. Trace the consumer of that metadata in the tokenizer before changing the producer.
8. Inspect the multiple-normalizer orchestration layer as well as individual normalizers. If metadata from the prior stage is saved and then freed without composition, fix composition at the chain boundary unless the semantics are truly normalizer-specific.

## Patching chained normalizers

When carrying a removed-blank boundary through a transformation:

- Do not copy character types by equal character index; replacements may be 1→N, N→1, or deletion.
- Use the downstream normalizer's **unmerged checks** to map its output back to the immediately preceding normalized string.
- A positive check starts a replacement group; following negative checks represent inserted output. Propagate a boundary to the final output character only when that boundary is at the **end of the consumed source group**. Do not OR every boundary found inside the group: a leading/deleted source boundary can otherwise split unrelated surviving output.
- Audit how general substitutor normalizers encode leading deletions. If deleted input occurs before any check exists, retain its byte length and fold it into the next positive check; otherwise raw checks no longer map output consumption to the preceding normalized string.
- Explicitly test leading deletion such as `u ab` with `u -> ""`: the result `ab` must not become `a|blank b`.
- Perform type propagation before existing code rewrites/merges checks to older source coordinates.
- If callers request types but not checks, generate checks internally only for the multi-normalizer composition and discard them afterward, restoring the caller-visible flags/state.
- Preserve only metadata whose semantics survive the stage. Recompute the base character class in the downstream normalizer; OR the boundary bit rather than replacing the entire type.

## Regression matrix

At minimum cover:

- no-op second normalizer with ASCII space;
- full-width space and newline when implicated;
- 1→N substitution, with the boundary on the last replacement character;
- N→1 substitution;
- deletion, including middle, trailing, **leading**, and all-delete cases;
- a leading-deletion guard such as `u ab` with `u -> ""`, which must not manufacture a boundary between `a` and `b`;
- token stream excludes a boundary-crossing N-gram;
- end-to-end search returns zero false matches;
- existing multiple-normalizer tests, especially metadata/offset tests.

## Verification

1. Build the real repository artifact.
2. Run the exact new regression test.
3. Run the complete normalizer test subtree.
4. Run `git diff --check`.
5. Export a patch including untracked new test files. `git diff` alone omits untracked files; use intent-to-add (`git add -N`) or another explicit inclusion method, then verify with `git apply --check` in a clean worktree.
6. Report the exact base commit and test counts. Distinguish “locally verified” from “accepted upstream.”

## Pitfalls

- `table_tokenize --mode GET` can return an empty list when the lexicon has not been populated; that is not proof that tokenization produced no terms.
- Do not create an out-of-source CMake build directory named `build` when the repository already tracks a source `build/` directory. Use a distinct absolute path such as `/tmp/project-build`.
- A pseudo-patch that calls a nonexistent merge helper is only a design sketch; the mapping helper and regression tests are the substantive fix.
- Updating an existing expected file can be correct when the old expectation encoded the bug. Explain why each changed boundary is semantically required.

## Session references

- See `references/chained-normalizer-boundaries.md` for a concrete metadata-mapping example and verification recipe distilled from a real Groonga bug investigation.
