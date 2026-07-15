---
requires_tools: [hermes_terminal]
name: laravel-boost
description: Use when working on Laravel application code with AI assistance, especially when Laravel Boost MCP/context should be considered before generating Laravel-specific code, tests, migrations, routes, queues, or frontend integration.
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [laravel, php, mcp, boost, ai-tools]
    related_skills: []
---

# Laravel Boost

## Overview

The user wants Laravel Boost remembered as the preferred Laravel AI-assistance context.

- Repository: `https://github.com/laravel/boost`
- Package: `laravel/boost`
- Documentation: `https://laravel.com/docs/boost`
- GitHub description observed: Laravel-focused MCP server for augmenting AI-powered local development.

Use this skill to bias Laravel work toward current Laravel conventions, project inspection, and Boost/MCP-provided context instead of generic PHP/Laravel guesses.

## When to Use

Use this skill for:

- Laravel controller, service, model, policy, request, job, listener, event, command, or notification work
- Migration/schema changes
- Route/middleware/auth work
- Queue/cache/session/filesystem/mail config changes
- Eloquent query behavior and performance review
- Laravel test generation or repair
- Laravel + Inertia/Svelte integration when Laravel-side behavior matters
- Setting up AI-assisted Laravel workflows

Do not use this as a substitute for reading the actual project files. Laravel apps vary heavily by version, package set, architecture, and local conventions.

## Required Inspection

Before recommending code changes, inspect available project state:

```sh
php artisan --version
composer show laravel/framework laravel/boost --no-interaction
composer show --direct --no-interaction
```

Check routes/config when relevant:

```sh
php artisan route:list
php artisan config:show app
php artisan about
```

For database-related tasks, inspect migrations and models before writing SQL or schema changes.

## Installation / Setup Reference

Laravel Boost is a Composer package. Prefer the official docs for current install steps:

```text
https://laravel.com/docs/boost
```

Do not install or modify project dependencies without explicit user approval. For production-like repositories, first inspect current `composer.json`, `composer.lock`, Laravel version, and branch cleanliness.

## Procedure

1. Identify Laravel version and relevant installed packages.
   Completion: `php artisan --version` or `composer show laravel/framework` result is known.
2. Inspect the exact files involved before proposing changes.
   Completion: routes/controllers/models/migrations/tests/config relevant to the task are read.
3. Prefer Laravel-native APIs and project conventions.
   Completion: generated code matches existing namespaces, validation style, response style, test framework, and formatting.
4. If Boost/MCP context is available, use it for Laravel-specific guidance.
   Completion: guidance is grounded in Boost/docs/tool output or uncertainty is stated.
5. Verify with the narrowest applicable checks.
   Completion: relevant tests/static checks run, or blocker is reported.

## Verification

Prefer narrow checks first:

```sh
php artisan test --filter='RelevantTestName'
./vendor/bin/pest --filter='RelevantTestName'
./vendor/bin/phpunit --filter='RelevantTestName'
```

Then broader checks when appropriate:

```sh
php artisan test
composer test
composer lint
```

For route/config changes:

```sh
php artisan route:list
php artisan config:clear
php artisan optimize:clear
```

Use destructive cache/config commands carefully in production; prefer staging or local verification first.

## Safety Constraints

- Do not run migrations, dependency upgrades, data-changing artisan commands, or production writes without explicit confirmation.
- Prefer read-only inspection first.
- For migrations, include rollback notes and data-risk notes.
- For dependency changes, inspect `composer.lock` and provide a rollback path.
- Do not store secrets from `.env` or credentials in skills/memory.

## Common Pitfalls

1. **Generic Laravel advice without version check.** Laravel APIs and defaults change by version.
2. **Changing migrations after deployment.** Prefer new migrations for deployed schemas unless explicitly told otherwise.
3. **Ignoring project test framework.** Detect Pest vs PHPUnit and match existing style.
4. **Assuming frontend stack.** Laravel may use Blade, Livewire, Inertia React/Vue/Svelte, or API-only patterns.
5. **Installing Boost automatically.** Treat dependency changes as writes requiring approval.

## Rollback / No-op Path

If the project context is missing, provide an inspection checklist and ask for the minimal files/output needed. Do not generalize one Laravel fix into a company standard without review.
