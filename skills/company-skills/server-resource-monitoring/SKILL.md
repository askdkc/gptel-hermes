---
name: server-resource-monitoring
description: Set up or report Linux server resource watchdogs (especially disk usage) with quiet threshold-crossing alerts.
version: 1.0.0
author: Hermes Agent
---

# Server Resource Monitoring

## Use when

- User asks for current `df -h` / filesystem capacity.
- User wants alerts when disk usage exceeds a threshold.
- User asks to change an existing resource-watch interval or threshold.

## Disk-usage watchdog

1. Inspect first with `df -h`; report actual output or a short verified summary.
2. For alert-only monitoring, create a stdlib Python script under `~/.hermes/profiles/main/scripts/` and a `cronjob(no_agent=true)` job.
3. Exclude ephemeral virtual filesystems (`tmpfs`, `devtmpfs`, `efivarfs`) unless explicitly requested. Check persistent mounts using `df -P -x tmpfs -x devtmpfs -x efivarfs`.
4. Success must be silent. On threshold crossing, print a concise alert containing mount, filesystem, usage percent, and free capacity.
5. Persist the set of mounts already over threshold. Alert once on crossing; clear that state after recovery so a later crossing alerts again. Do not notify repeatedly every interval.
6. Test the live healthy path (silent, exit 0) and a synthetic `df` sample above threshold before scheduling.
7. Use the user's requested schedule; if absent, ask only if cadence materially affects the alert's value. When changed, update both cron schedule and its human-readable prompt.

## Reporting

State interval, threshold, monitored scope, notification behavior, and that continuous over-threshold conditions are deduplicated. Do not claim a job is active before script tests and cron creation both succeed.

## Safety

- Treat filesystem cleanup as separate, destructive work; never automate deletion merely because an alert exists.
- Preserve normal process exit (`0`) for detected resource conditions so the scheduler delivers the clear alert instead of a watchdog-crash error.
