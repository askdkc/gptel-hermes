---
requires_tools: [hermes_skill_view, hermes_skill_resource_path, hermes_terminal_authenticated]
name: google-workspace
description: "Gmail, Calendar, Drive, Docs, Sheets via gws CLI or Python."
version: 1.1.0
author: Nous Research
license: MIT
platforms: [linux, macos, windows]
required_credential_files:
  - path: google_token.json
    description: Google OAuth2 token (created by setup script)
  - path: google_client_secret.json
    description: Google OAuth2 client credentials (downloaded from Google Cloud Console)
metadata:
  hermes:
    tags: [Google, Gmail, Calendar, Drive, Sheets, Docs, Contacts, Email, OAuth]
    homepage: https://github.com/NousResearch/hermes-agent
    related_skills: [himalaya]
---

# Google Workspace

Gmail, Calendar, Drive, Contacts, Sheets, and Docs — through Hermes-managed OAuth and a thin CLI wrapper. When `gws` is installed, the skill uses it as the execution backend for broader Google Workspace coverage; otherwise it falls back to the bundled Python client implementation.

Run non-interactive commands below through `hermes_terminal_authenticated`.
The user must complete browser consent and any interactive setup outside the
tool; terminal stdin is closed.

## References

- `references/gmail-search-syntax.md` — Gmail search operators (is:unread, from:, newer_than:, etc.)

## Scripts

- `scripts/setup.py` — OAuth2 setup (run once to authorize)
- `scripts/google_api.py` — compatibility wrapper CLI. It prefers `gws` for operations when available, while preserving Hermes' existing JSON output contract.

## First-Time Setup

The setup is fully non-interactive — you drive it step by step so it works
on CLI, Telegram, Discord, or any platform.

Resolve the bundled setup script first:

```text
hermes_skill_resource_path(name="google-workspace", resource="scripts/setup.py")
```

Use its returned absolute `Effective path` directly in every terminal call.
Do not define a shell variable: each `hermes_terminal_authenticated` call is
a fresh process.

For example, the following is one tool call (the returned path is one argv
element even when it contains spaces):

```python
hermes_terminal_authenticated(
    program="python3",
    arguments=["/absolute/path/returned-by-hermes_skill_resource_path", "--check"])
```

```bash
python3 "/absolute/path/returned-by-hermes_skill_resource_path" --check
```

### Step 0: Check if already set up

```bash
python3 "/absolute/path/returned-by-hermes_skill_resource_path" --check
```

If it prints `AUTHENTICATED`, skip to Usage — setup is already done.

### Step 1: Triage — ask the user what they need

Before starting OAuth setup, ask the user TWO questions:

**Question 1: "What Google services do you need? Just email, or also
Calendar/Drive/Sheets/Docs?"**

- **Email only** → They don't need this skill at all. Use the `himalaya` skill
  instead — it works with a Gmail App Password (Settings → Security → App
  Passwords) and takes 2 minutes to set up. No Google Cloud project needed.
  Load the himalaya skill and follow its setup instructions.

- **Email + Calendar** → Continue with this skill, but use
  `--services email,calendar` during auth so the consent screen only asks for
  the scopes they actually need.

- **Calendar/Drive/Sheets/Docs only** → Continue with this skill and use a
  narrower `--services` set like `calendar,drive,sheets,docs`.

- **Full Workspace access** → Continue with this skill and use the default
  `all` service set.

**Question 2: "Does your Google account use Advanced Protection (hardware
security keys required to sign in)? If you're not sure, you probably don't
— it's something you would have explicitly enrolled in."**

- **No / Not sure** → Normal setup. Continue below.
- **Yes** → Their Workspace admin must add the OAuth client ID to the org's
  allowed apps list before Step 4 will work. Let them know upfront.

### Step 2: Create OAuth credentials (one-time, ~5 minutes)

Tell the user:

> You need a Google Cloud OAuth client. This is a one-time setup:
>
> 1. Create or select a project:
>    https://console.cloud.google.com/projectselector2/home/dashboard
> 2. Enable the required APIs from the API Library:
>    https://console.cloud.google.com/apis/library
>    Enable: Gmail API, Google Calendar API, Google Drive API,
>    Google Sheets API, Google Docs API, People API
> 3. Create the OAuth client here:
>    https://console.cloud.google.com/apis/credentials
>    Credentials → Create Credentials → OAuth 2.0 Client ID
> 4. Application type: "Desktop app" → Create
> 5. If the app is still in Testing, add the user's Google account as a test user here:
>    https://console.cloud.google.com/auth/audience
>    Audience → Test users → Add users
> 6. Download the JSON file and tell me the file path
>
> Important Hermes CLI note: if the file path starts with `/`, do NOT send only the bare path as its own message in the CLI, because it can be mistaken for a slash command. Send it in a sentence instead, like:
> `The JSON file path is: /home/user/Downloads/client_secret_....json`

Once they provide the path:

```bash
python3 "/absolute/path/returned-by-hermes_skill_resource_path" --client-secret /path/to/client_secret.json
```

If they paste the raw client ID / client secret values instead of a file path,
write a valid Desktop OAuth JSON file for them yourself, save it somewhere
explicit (for example `~/Downloads/hermes-google-client-secret.json`), then run
`--client-secret` against that file.

### Step 3: Get authorization URL

Use the service set chosen in Step 1. Examples:

```bash
python3 "/absolute/path/returned-by-hermes_skill_resource_path" --auth-url --services email,calendar --format json
python3 "/absolute/path/returned-by-hermes_skill_resource_path" --auth-url --services calendar,drive,sheets,docs --format json
python3 "/absolute/path/returned-by-hermes_skill_resource_path" --auth-url --services all --format json
```

This returns JSON with an `auth_url` field and also saves the exact URL to
`~/.hermes/google_oauth_last_url.txt`.

Agent rules for this step:
- Extract the `auth_url` field and send that exact URL to the user as a single line.
- Tell the user that the browser will likely fail on `http://localhost:1` after approval, and that this is expected.
- Tell them to copy the ENTIRE redirected URL from the browser address bar.
- If the user gets `Error 403: access_denied`, send them directly to `https://console.cloud.google.com/auth/audience` to add themselves as a test user.

### Step 4: Exchange the code

The user will paste back either a URL like `http://localhost:1/?code=4/0A...&scope=...`
or just the code string. Either works. The `--auth-url` step stores a temporary
pending OAuth session locally so `--auth-code` can complete the PKCE exchange
later, even on headless systems:

```bash
python3 "/absolute/path/returned-by-hermes_skill_resource_path" --auth-code "THE_URL_OR_CODE_THE_USER_PASTED" --format json
```

If `--auth-code` fails because the code expired, was already used, or came from
an older browser tab, it now returns a fresh `fresh_auth_url`. In that case,
immediately send the new URL to the user and have them retry with the newest
browser redirect only.

### Step 5: Verify

```bash
python3 "/absolute/path/returned-by-hermes_skill_resource_path" --check
```

Should print `AUTHENTICATED`. Setup is complete — token refreshes automatically from now on.

### Notes

- Token is stored at `~/.hermes/google_token.json` and auto-refreshes.
- Pending OAuth session state/verifier are stored temporarily at `~/.hermes/google_oauth_pending.json` until exchange completes.
- If `gws` is installed, `google_api.py` points it at the same `~/.hermes/google_token.json` credentials file. Users do not need to run a separate `gws auth login` flow.
- To revoke: `python3 "/absolute/path/returned-by-hermes_skill_resource_path" --revoke`

## Usage

Resolve the API script with
`hermes_skill_resource_path(name="google-workspace", resource="scripts/google_api.py")`.
Use its returned absolute `Effective path` directly in every terminal call; do
not define a shell variable.

```bash
python3 "/absolute/path/returned-by-hermes_skill_resource_path" gmail search "is:unread" --max 10
```

### Gmail

```bash
# Search (returns JSON array with id, from, subject, date, snippet)
python3 "/absolute/path/returned-by-hermes_skill_resource_path" gmail search "is:unread" --max 10
python3 "/absolute/path/returned-by-hermes_skill_resource_path" gmail search "from:boss@company.com newer_than:1d"
python3 "/absolute/path/returned-by-hermes_skill_resource_path" gmail search "has:attachment filename:pdf newer_than:7d"

# Read full message (returns JSON with body text)
python3 "/absolute/path/returned-by-hermes_skill_resource_path" gmail get MESSAGE_ID

# Send
python3 "/absolute/path/returned-by-hermes_skill_resource_path" gmail send --to user@example.com --subject "Hello" --body "Message text"
python3 "/absolute/path/returned-by-hermes_skill_resource_path" gmail send --to user@example.com --subject "Report" --body "<h1>Q4</h1><p>Details...</p>" --html
python3 "/absolute/path/returned-by-hermes_skill_resource_path" gmail send --to user@example.com --subject "Hello" --from '"Research Agent" <user@example.com>' --body "Message text"

# Reply (automatically threads and sets In-Reply-To)
python3 "/absolute/path/returned-by-hermes_skill_resource_path" gmail reply MESSAGE_ID --body "Thanks, that works for me."
python3 "/absolute/path/returned-by-hermes_skill_resource_path" gmail reply MESSAGE_ID --from '"Support Bot" <user@example.com>' --body "Thanks"

# Labels
python3 "/absolute/path/returned-by-hermes_skill_resource_path" gmail labels
python3 "/absolute/path/returned-by-hermes_skill_resource_path" gmail modify MESSAGE_ID --add-labels LABEL_ID
python3 "/absolute/path/returned-by-hermes_skill_resource_path" gmail modify MESSAGE_ID --remove-labels UNREAD
```

### Calendar

```bash
# List events (defaults to next 7 days)
python3 "/absolute/path/returned-by-hermes_skill_resource_path" calendar list
python3 "/absolute/path/returned-by-hermes_skill_resource_path" calendar list --start 2026-03-01T00:00:00Z --end 2026-03-07T23:59:59Z

# Create event (ISO 8601 with timezone required)
python3 "/absolute/path/returned-by-hermes_skill_resource_path" calendar create --summary "Team Standup" --start 2026-03-01T10:00:00-06:00 --end 2026-03-01T10:30:00-06:00
python3 "/absolute/path/returned-by-hermes_skill_resource_path" calendar create --summary "Lunch" --start 2026-03-01T12:00:00Z --end 2026-03-01T13:00:00Z --location "Cafe"
python3 "/absolute/path/returned-by-hermes_skill_resource_path" calendar create --summary "Review" --start 2026-03-01T14:00:00Z --end 2026-03-01T15:00:00Z --attendees "alice@co.com,bob@co.com"

# Delete event
python3 "/absolute/path/returned-by-hermes_skill_resource_path" calendar delete EVENT_ID
```

### Drive

```bash
# Search existing files
python3 "/absolute/path/returned-by-hermes_skill_resource_path" drive search "quarterly report" --max 10
python3 "/absolute/path/returned-by-hermes_skill_resource_path" drive search "mimeType='application/pdf'" --raw-query --max 5

# Get metadata for a single file
python3 "/absolute/path/returned-by-hermes_skill_resource_path" drive get FILE_ID

# Upload a local file (auto-detects MIME type)
python3 "/absolute/path/returned-by-hermes_skill_resource_path" drive upload /path/to/report.pdf
python3 "/absolute/path/returned-by-hermes_skill_resource_path" drive upload /path/to/image.png --name "Logo.png" --parent FOLDER_ID

# Download (binary files download as-is; Google-native files export to a
# sensible default — Docs→pdf, Sheets→csv, Slides→pdf, Drawings→png)
python3 "/absolute/path/returned-by-hermes_skill_resource_path" drive download FILE_ID
python3 "/absolute/path/returned-by-hermes_skill_resource_path" drive download DOC_ID --output ~/doc.pdf
python3 "/absolute/path/returned-by-hermes_skill_resource_path" drive download DOC_ID --export-mime text/plain --output ~/doc.txt

# Create a folder
python3 "/absolute/path/returned-by-hermes_skill_resource_path" drive create-folder "Reports"
python3 "/absolute/path/returned-by-hermes_skill_resource_path" drive create-folder "Q4" --parent FOLDER_ID

# Share
python3 "/absolute/path/returned-by-hermes_skill_resource_path" drive share FILE_ID --email alice@example.com --role reader
python3 "/absolute/path/returned-by-hermes_skill_resource_path" drive share FILE_ID --email alice@example.com --role writer --notify
python3 "/absolute/path/returned-by-hermes_skill_resource_path" drive share FILE_ID --type anyone --role reader        # anyone with link
python3 "/absolute/path/returned-by-hermes_skill_resource_path" drive share FILE_ID --type domain --domain example.com --role reader

# Delete — defaults to trash (reversible). Use --permanent to skip the trash.
python3 "/absolute/path/returned-by-hermes_skill_resource_path" drive delete FILE_ID
python3 "/absolute/path/returned-by-hermes_skill_resource_path" drive delete FILE_ID --permanent
```

### Contacts

```bash
python3 "/absolute/path/returned-by-hermes_skill_resource_path" contacts list --max 20
```

### Sheets

```bash
# Create a new spreadsheet
python3 "/absolute/path/returned-by-hermes_skill_resource_path" sheets create --title "Q4 Budget"
python3 "/absolute/path/returned-by-hermes_skill_resource_path" sheets create --title "Inventory" --sheet-name "Stock"

# Read
python3 "/absolute/path/returned-by-hermes_skill_resource_path" sheets get SHEET_ID "Sheet1!A1:D10"

# Write
python3 "/absolute/path/returned-by-hermes_skill_resource_path" sheets update SHEET_ID "Sheet1!A1:B2" --values '[["Name","Score"],["Alice","95"]]'

# Append rows
python3 "/absolute/path/returned-by-hermes_skill_resource_path" sheets append SHEET_ID "Sheet1!A:C" --values '[["new","row","data"]]'
```

### Docs

```bash
# Read
python3 "/absolute/path/returned-by-hermes_skill_resource_path" docs get DOC_ID

# Create a new Doc (optionally seeded with body text)
python3 "/absolute/path/returned-by-hermes_skill_resource_path" docs create --title "Meeting Notes"
python3 "/absolute/path/returned-by-hermes_skill_resource_path" docs create --title "Draft" --body "First paragraph..."

# Append text to the end of an existing Doc
python3 "/absolute/path/returned-by-hermes_skill_resource_path" docs append DOC_ID --text "Additional content to append"
```

## Output Format

All commands return JSON. Parse with `jq` or read directly. Key fields:

- **Gmail search**: `[{id, threadId, from, to, subject, date, snippet, labels}]`
- **Gmail get**: `{id, threadId, from, to, subject, date, labels, body}`
- **Gmail send/reply**: `{status: "sent", id, threadId}`
- **Calendar list**: `[{id, summary, start, end, location, description, htmlLink}]`
- **Calendar create**: `{status: "created", id, summary, htmlLink}`
- **Drive search**: `[{id, name, mimeType, modifiedTime, webViewLink}]`
- **Drive get**: `{id, name, mimeType, modifiedTime, size, webViewLink, parents, owners}`
- **Drive upload**: `{status: "uploaded", id, name, mimeType, webViewLink}`
- **Drive download**: `{status: "downloaded", id, name, path, mimeType}`
- **Drive create-folder**: `{status: "created", id, name, webViewLink}`
- **Drive share**: `{status: "shared", permissionId, fileId, role, type}`
- **Drive delete**: `{status: "trashed" | "deleted", fileId, permanent}`
- **Contacts list**: `[{name, emails: [...], phones: [...]}]`
- **Sheets get**: `[[cell, cell, ...], ...]`
- **Sheets create**: `{status: "created", spreadsheetId, title, spreadsheetUrl}`
- **Docs create**: `{status: "created", documentId, title, url}`
- **Docs append**: `{status: "appended", documentId, inserted_at, characters}`

## Rules

1. **Never send email, create/delete calendar events, delete Drive files, share files, or modify Docs/Sheets without confirming with the user first.** Show what will be done (recipients, file IDs, content, share role) and ask for approval. For `drive delete`, prefer the default trash (reversible) over `--permanent`.
2. **Check auth before first use** — run the resolved setup path with
   `--check` as shown above. If it fails, guide the user through setup.
3. **Use the Gmail search syntax reference** for complex queries — load it with `hermes_skill_view(name="google-workspace", resource="references/gmail-search-syntax.md")`.
4. **Calendar times must include timezone** — always use ISO 8601 with offset (e.g., `2026-03-01T10:00:00-06:00`) or UTC (`Z`).
5. **Respect rate limits** — avoid rapid-fire sequential API calls. Batch reads when possible.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `NOT_AUTHENTICATED` | Run setup Steps 2-5 above |
| `REFRESH_FAILED` | Token revoked or expired — redo Steps 3-5 |
| `HttpError 403: Insufficient Permission` | Missing API scope — `python3 "/absolute/path/returned-by-hermes_skill_resource_path" --revoke` then redo Steps 3-5 |
| `AUTHENTICATED (partial)` or "Token missing scopes" | New write capabilities (Drive write/delete, Docs create/edit) require re-authorization. `python3 "/absolute/path/returned-by-hermes_skill_resource_path" --revoke` then redo Steps 3-5 to grant the upgraded scopes. |
| `HttpError 403: Access Not Configured` | API not enabled — user needs to enable it in Google Cloud Console |
| `ModuleNotFoundError` | Run `python3 "/absolute/path/returned-by-hermes_skill_resource_path" --install-deps` |
| Advanced Protection blocks auth | Workspace admin must allowlist the OAuth client ID |

## Revoking Access

```bash
python3 "/absolute/path/returned-by-hermes_skill_resource_path" --revoke
```
