# Chained normalizer boundary propagation

## Symptom pattern

A first normalizer removes whitespace and records the boundary on the preceding character type:

```text
"abc def" -> "abcdef"
types: alpha alpha alpha|blank alpha alpha alpha
```

A later table normalizer receives only `abcdef`, regenerates character classes, and can lose `GRN_CHAR_BLANK`. `TokenNgram("unify_alphabet", false)` then emits the invalid cross-boundary bigram `cd`, enabling false matches such as `cde`.

## Where to inspect

In Groonga's multiple-normalizer orchestration, inspect the stage that saves prior `normalized`, `checks`, `ctypes`, and `offsets`. If prior `ctypes` is merely freed while checks/offsets are composed, the orchestration layer is dropping boundary metadata.

The tokenizer consumes the blank bit to stop N-gram extension, so changing tokenizer behavior is usually the wrong layer.

## Correct mapping model

The downstream normalizer's raw checks map its output to the immediately preceding normalized text:

- `check > 0`: start of an output/replacement group; value is consumed input bytes.
- `check < 0`: inserted output associated with the current replacement group.
- continuation bytes use zero values.

Algorithm:

1. Walk output characters using raw downstream checks.
2. Accumulate consumed bytes in the previous normalized string.
3. For each positive-check source group, inspect whether the **last consumed source character** carries `GRN_CHAR_BLANK`.
4. Do not propagate a blank found only inside the consumed group. It may belong to leading/deleted input; moving it to the group's output would manufacture a later boundary.
5. Delay a valid end-of-group boundary through negative-check inserted output.
6. At the next positive check, apply it to the preceding output character—the end of the previous replacement group.
7. Apply a remaining valid boundary to the final output character.
8. Only after this, run the existing checks/offset composition.

This handles identity, 1→N, N→1, and deletion when raw checks account for all consumed source bytes. Equal-index OR does not.

### Leading-deletion trap

A substitutor may delete source before it has emitted any output/check. If it simply returns while the checks vector is empty, the next output check omits the deleted byte count. The composition layer then cannot distinguish:

```text
u|blank ab --(u -> "")--> ab
```

from a replacement group consuming only `u`, and may incorrectly produce `a|blank b`.

For general substitutor normalizers, carry a `pending_source_length` while there is no check owner and add it to the next positive check. Then the source group for the first surviving `a` consumes both deleted `u` and `a`; because the blank is internal rather than at the group's end, it is dropped instead of moved after `a`. Add a regression that proves `u ab` normalizes to `ab` with no blank on `a`.

## Minimal regression recipe

Use a `NormalizerNFKC150, NormalizerTable(...)` chain and test all of:

```text
abc def   # no-op table mapping; must not emit cd
q b       # q -> xy; blank must land on y
rs t      # rs -> z; blank must land on z
a u b     # u -> empty; surviving preceding output retains boundary
u ab      # u -> empty at the beginning; must remain ab, not a|blank b
```

Populate an indexed lexicon before `table_tokenize ... --mode GET`; otherwise GET may return no terms for an unrelated reason. Assert both:

- token list excludes the cross-boundary token;
- end-to-end `select` for a constructed cross-boundary query returns zero rows.

## Patch packaging checklist

- Build succeeds.
- New regression test passes.
- Full normalizer subtree passes.
- `git diff --check` passes.
- Newly created tests are present in the exported patch (`git diff` omits ordinary untracked files).
- `git apply --check` succeeds against the recorded base commit.
