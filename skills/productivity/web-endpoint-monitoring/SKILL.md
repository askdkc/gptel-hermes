---
requires_tools: [hermes_skill_resource_path, hermes_terminal_authenticated, cronjob]
name: web-endpoint-monitoring
description: "Use when setting up recurring watchdogs for URLs, API endpoints, rendered images, embedded data images, or simple availability checks that should notify only on abnormal conditions."
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [monitoring, cron, watchdog, urls, http, availability]
    related_skills: [hermes-agent, blogwatcher, dogfood]
---

# Web Endpoint Monitoring

Run probes, script creation, and cron setup through
`hermes_terminal_authenticated`: this workflow persists scripts under the
user's real `~/.hermes/scripts/` directory. Use a workspace path instead if a
standard temporary-home terminal is required.

## Overview

Use this skill when the user asks to periodically check a URL or API and report only failures: missing images, non-2xx HTTP responses, error strings in the body, malformed payloads, stale data, or broken redirects. The goal is a quiet watchdog: normal runs produce no message; abnormal runs produce a concise actionable alert in the origin chat.

Prefer a deterministic script plus a `cronjob(no_agent=true)` schedule for simple checks. Use an agent-driven cron job only when the result needs judgment, synthesis, ranking, or narrative summarization.

## When to Use

- "Check this URL every N minutes and tell me if it breaks."
- "Notify me if the page stops showing an image / QR / expected element."
- "Alert only on HTTP errors or error codes in the response."
- "Poll this endpoint and stay silent when everything is normal."

Don't use this for:

- RSS/blog/news monitoring with summarization — use a feed/blog monitoring skill instead.
- Full browser QA that needs clicking, screenshots, login, or visual interaction — use `dogfood` / browser automation.
- Sensitive authenticated checks unless the user explicitly provides and approves the credential handling path.

## Standard Workflow

1. **Probe the endpoint once.** Fetch it with a real HTTP request, record status, content type, size, and a tiny content sample. Completion criterion: you know what "healthy" actually looks like (direct image bytes, HTML containing `data:image`, JSON field, etc.).

2. **Define explicit failure predicates.** Common predicates:
   - HTTP status outside 2xx.
   - Network/timeout exception.
   - Empty body or an unexpected content type.
   - For ordinary HTML sites, a stable site-identity marker is missing (prefer the exact `<title>` text, product/site heading, or another durable page-specific string observed in the healthy probe).
   - Expected image bytes missing or invalid PNG/JPEG signature.
   - Expected embedded `data:image/...;base64` missing, undecodable, too small, or not image bytes.
   - Body contains a known, site-specific error phrase/code when there is evidence it denotes failure.
   Avoid broad body regexes such as bare `4\d\d`, `5\d\d`, `error`, or `not found` on normal HTML pages: JavaScript, CSS, analytics, links, and legitimate prose often contain them. Prefer HTTP status plus a positive health marker.
   Completion criterion: every user-stated failure condition maps to a concrete test with low false-positive risk.

3. **Write a quiet script under `~/.hermes/scripts/`.** The script prints nothing on success and prints the exact alert message on failure. It should exit `0` for both normal and detected-abnormal states so the scheduler sends only the scripted alert, not a stack trace. Reserve non-zero exits for broken watchdog code.

4. **Test both the live healthy path and at least one synthetic bad path when practical.** For synthetic tests, parameterize URL or expected marker so a bad input can trigger the alert without editing the production script. Completion criterion: healthy run is silent; failure run prints a useful alert.

5. **Create a script-only cron job.** Use `cronjob(action='create', schedule='every 10m', script='<filename>', no_agent=true, deliver='origin')`. The `script` path must be relative to `~/.hermes/scripts/` (for example `qr_image_watch.py`, not `/home/.../qr_image_watch.py`). Completion criterion: cron creation returns a job ID and next run time.

6. **Report the contract.** Tell the user the interval, URL, notification conditions, normal silence behavior, and job ID. Do not paste long script bodies unless asked.

## Bundled starters

The starter files are package resources, not workspace-relative files. Before
copying one into the persistent `~/.hermes/scripts/` directory, resolve it with
`hermes_skill_resource_path(name="web-endpoint-monitoring", resource="scripts/http_image_watch.py")`
or the corresponding `templates/html-site-watch.py` resource and use the
returned absolute `Effective path` in the copy command.

## Implementation Notes

- Put reusable scripts in the persistent `~/.hermes/scripts/` directory. Use
  the resolved `scripts/http_image_watch.py` resource as a parameterized
  image/embedded-data-image watchdog starter.
- For ordinary HTML pages, copy the resolved `templates/html-site-watch.py`
  resource into `~/.hermes/scripts/` and customize `URL`, `LABEL`,
  `EXPECTED_MARKER`, and optionally `EXPECTED_PATH`.
- Choose a stable marker from the live healthy page—usually the exact `<title>` or a product/site heading. For SPA shells where record data loads client-side, validate the stable application title plus the final URL path rather than requiring dynamic record text in the initial HTML.
- When redirects are expected (for example HTTP→HTTPS), allow them but validate `response.geturl()` host/path so a redirect to a generic error, login, or home page does not count as healthy.
- Put session-specific endpoint notes in `references/` when the health shape is unusual. See `references/qr-data-image-watchdog.md` for the QR-as-HTML-`data:image` pattern.
- For `no_agent=true`, empty stdout means silent. Non-empty stdout is delivered verbatim. Non-zero exit sends an error alert, which is useful for code failures but noisy for expected endpoint failures.
- Keep alerts short and diagnostic: timestamp, URL, reason, HTTP status, content type, and a trimmed detail/sample.
- Format alert timestamps in JST (`Asia/Tokyo`) when the user prefers Japanese/JST monitoring notifications; do not emit raw UTC ISO timestamps.
- For `no_agent=true` jobs, distinguish the script's stdout from any scheduler-generated wrapper metadata. Test the exact delivered message when timestamp formatting matters.
- Prefer stdlib Python (`urllib.request`, `base64`, `re`) for small watchdogs so the cron job has no package dependency.
- Parameterize the target with a `WATCH_URL` environment override when practical. Verify the live healthy path is silent, then run once against a guaranteed bad local URL such as `http://127.0.0.1:9/` to prove the alert path without changing production constants.
- If the endpoint returns HTML containing a base64 data URL, validate the decoded bytes, not just the string prefix.

## Common Pitfalls

1. **Using an absolute script path in `cronjob`.** Cron script paths are relative to `~/.hermes/scripts/`; absolute and home-relative paths are rejected.

2. **Not checking the real healthy shape first.** Many QR/image endpoints return HTML with embedded `data:image` rather than direct `image/png`. Probe before writing the predicate.

3. **Noisy success output.** A watchdog that prints "OK" every run will spam the user. Success must be silent for alert-only monitoring.

4. **Treating detected endpoint failure as process failure.** If the endpoint is down, print an alert and exit `0`; otherwise the scheduler may wrap it as a script crash instead of the clear user-facing message.

5. **Misreading a quiet-success test as a script failure.** Shell checks like `[ -n "$out" ] && printf ...` leave status `1` when output is correctly empty, even if the watchdog itself exited `0`. Capture and report the watchdog's exit code separately, or use a small `subprocess.run(..., capture_output=True)` harness that verifies `returncode == 0`, empty stdout, and empty stderr.

6. **Over-hardening one site's transient behavior into a global rule.** Capture the pattern (validate status/content/body/image bytes), not a permanent claim that a provider or tool is broken.

## Verification Checklist

- [ ] Live probe confirms the expected healthy response shape.
- [ ] Script is under `~/.hermes/scripts/` and uses a relative filename in cron.
- [ ] Healthy run prints nothing and exits `0`.
- [ ] Failure predicates match every user-stated alert condition.
- [ ] Cron job uses `no_agent=true` for deterministic alert-only checks.
- [ ] User receives interval, notification conditions, normal-silence behavior, and job ID.
