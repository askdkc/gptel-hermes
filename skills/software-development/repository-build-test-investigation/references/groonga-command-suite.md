# Groonga command-suite investigation example

Session context: Groonga issue #2853, a false positive caused by losing a blank-boundary character-type flag between chained normalizers. This file captures reusable repository-specific commands, not a fix.

## Relevant files

- Build docs: `doc/source/install/cmake.md`
- Presets: `CMakePresets.json`
- Test wrapper: `test/command/run-test.sh`
- Command tests: `test/command/suite/`
- Closest invariant test:
  - `test/command/suite/normalizers/multiple/options/remove_blank.test`
  - `test/command/suite/normalizers/multiple/options/remove_blank.expected`

## Why this is the minimal regression seam

The user-visible failure is a full-text false positive: an N-gram crosses whitespace after `NormalizerNFKC150, NormalizerTable(...)`. The lower-level invariant is that `GRN_CHAR_BLANK` on the character preceding removed whitespace must survive the next normalizer.

The existing `remove_blank.test` already asserts `REMOVE_BLANK|WITH_TYPES|WITH_CHECKS` for multiple normalizers, but covered the reverse order (`NormalizerTable, NormalizerNFKC150`). Add the forward order rather than creating a full table/index/select reproduction. The expected `types` must retain `alpha|blank` on the pre-boundary character.

## Verified out-of-tree build

```bash
cmake \
  -S /tmp/groonga-2853 \
  -B /tmp/groonga-build-2853 \
  -G Ninja \
  -DCMAKE_BUILD_TYPE=Debug \
  -DGRN_WITH_MRUBY=OFF \
  -DGRN_WITH_APACHE_ARROW=OFF

cmake --build /tmp/groonga-build-2853 -j2
```

This built successfully on Linux/aarch64. Even with mruby and Arrow disabled, auto-detected optional components such as llama.cpp can make the build large; do not invent additional disable flags—verify them in CMake metadata first.

## Test runner setup

CI installs the Ruby runner with:

```bash
gem install --user-install grntest
export PATH="$(ruby -e 'print Gem.user_dir')/bin:$PATH"
```

`test/command/run-test.sh` behavior:

- `SOURCE_DIR` is the source `test/command` directory.
- `BUILD_DIR` defaults to `SOURCE_DIR`.
- The build root is two directories above `BUILD_DIR`.
- If that root contains `build.ninja`, the wrapper rebuilds with Ninja.
- The generated build `config.sh` supplies `GROONGA`, `RUBY`, and related executable paths.
- `NO_BUILD=yes` skips the wrapper's rebuild.

Therefore an out-of-tree build must be selected as follows:

```bash
export PATH="$(ruby -e 'print Gem.user_dir')/bin:$PATH"
BUILD_DIR=/tmp/groonga-build-2853/test/command \
  ./test/command/run-test.sh \
  --reporter=stream \
  test/command/suite/normalizers/multiple/options/remove_blank.test
```

Observed result before source changes: 1 test, 1 pass, 0 failures, 100% passed. This verifies the invocation path; the new #2853 case should be red before the fix.

## Setup-script warning

`setup.sh` starts package-manager operations immediately and does not implement a harmless `--help` path. Read it instead of probing it. On Debian/Ubuntu it adds the Apache Arrow APT source and installs build dependencies.

## Hygiene

Keep builds in `/tmp/groonga-build-*`, issue JSON in `/tmp`, and check `git status --short` before and after. Do not point exploratory CMake inspection at the repository's tracked `build/` subtree.
