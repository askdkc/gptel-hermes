---
name: repository-build-test-investigation
description: "Investigate how an unfamiliar repository builds and runs tests, locate the smallest regression-test seam, and verify commands without modifying source files."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [repository, build, tests, regression-test, read-only, cmake]
    related_skills: [systematic-debugging, test-driven-development, codebase-inspection]
---

# Repository Build and Test Investigation

Use this skill when the user wants build instructions, test invocation, or the best regression-test location in an unfamiliar repository—especially when source changes are forbidden.

## Goals

Produce verified, copy-pasteable answers for:

1. Dependency/setup procedure.
2. Configure and build commands.
3. Full-suite and narrow-test commands.
4. The smallest regression-test placement, justified by nearby patterns.
5. Actual execution results and final repository cleanliness.

## Workflow

### 1. Establish the boundary

- Run `git status --short` before any command and preserve its output.
- Record the repository root and current commit.
- Distinguish **source changes** from allowed out-of-tree build artifacts, temporary issue data, and user-level tooling.
- If the tree starts dirty, do not clean or overwrite anything you did not create.

### 2. Inspect before executing

Read, in this order:

1. Top-level build metadata (`CMakePresets.json`, `CMakeLists.txt`, Meson/Autotools files, package manifests).
2. Build documentation.
3. Test wrapper scripts.
4. CI jobs that invoke the relevant suite.
5. Existing tests around the affected component and behavior.

Do not invoke a repository script merely with `--help` until inspection confirms it parses help before side effects. Shell setup scripts commonly ignore arguments and immediately install packages.

### 3. Resolve the external issue from its original source

If an issue or PR number is given, inspect the live issue/PR first. Capture:

- Exact symptom and expected behavior.
- Minimal reproduction input.
- Relevant environment or feature flags.
- Maintainer comments that narrow the root cause.

Session history and code search are secondary context, not substitutes for the issue itself.

### 4. Find the regression-test seam

Search by both feature name and underlying invariant. Compare:

- Tests for the user-visible command.
- Tests for the lower-level data or metadata that causes the symptom.
- Existing tests for option order, multiple stages, boundary conditions, and expected output.

Prefer the lowest stable seam that directly asserts the broken invariant. A small normalization/type test is often better than recreating a full indexing/search pipeline if the search failure is only a downstream consequence. Recommend an end-to-end test only when the lower-level assertion could pass while user-visible behavior remains broken.

When an existing test already covers the same matrix but misses one order or boundary, extend that `.test`/`.expected` pair rather than creating a new one-test directory.

### 5. Build out of tree

Use a fresh directory outside the repository unless upstream explicitly requires in-tree builds:

```bash
cmake -S /path/to/source -B /tmp/project-build -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build /tmp/project-build -j2
```

Why:

- A source directory named `build/` may contain tracked project files.
- Exploratory CMake commands can populate the wrong directory.
- Cleanup is safe only when the build directory was created solely for this task.

Use documented presets/options where possible. For a narrow test investigation, disable expensive optional features only when the option names and values are verified from project metadata.

### 6. Understand and run the wrapper

Read the test wrapper completely enough to determine:

- How it derives source and build roots.
- Whether it rebuilds automatically.
- Which environment variable selects an out-of-tree build.
- How a single file/directory target is recognized.
- Required external runners and how CI installs them.

Run the closest existing test before proposing a new test path. Report the exact target, pass/fail count, and runner version.

### 7. Verify cleanliness and report side effects

At the end:

```bash
git status --short
```

- It should match the initial status for a read-only task.
- Remove only artifacts proven to be yours.
- Never run broad `git clean` in a shared/pre-existing tree.
- Report out-of-repository build directories, temporary downloads, user-level package installs, and system package changes separately.

## Output format

Keep the result operational and concise:

1. **Recommended minimal test location** and why.
2. **Exact narrow-test command**, including required environment variables.
3. **Exact configure/build commands** that were actually verified.
4. **Observed output**: versions and pass/fail summary.
5. **Cleanliness/side effects**.
6. **Pitfalls**, only when actionable.

## Pitfalls

- Do not use an unrelated codebase-metrics skill merely because the task says “inspect a repository.”
- Do not infer a test command only from file layout; verify the wrapper or CI invocation.
- Do not assume a missing global test runner blocks testing; wrappers may vendor/clone it when a language runtime variable is configured.
- Do not call setup scripts for discovery. Read them first.
- Do not build into a tracked `build/` subtree.
- Do not call a full suite when one nearby test proves the invocation method.
- Do not claim the source tree is untouched without a final status check.

## References

- `references/groonga-command-suite.md` — Groonga-specific CMake, `grntest`, wrapper-root derivation, and regression-test placement example from issue #2853.
