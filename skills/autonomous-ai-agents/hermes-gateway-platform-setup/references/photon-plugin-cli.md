# Photon/iMessage plugin CLI registration notes

This reference captures a workflow observed while setting up Photon/iMessage for Hermes.

## Symptom

`hermes photon setup` returned an argparse error like:

```text
hermes: error: argument command: invalid choice: 'photon'
```

But `hermes plugins list` showed the bundled Photon platform plugin:

```text
photon-platform  not enabled  ...  The plugin ships with a `hermes photon` CLI ...
```

After running:

```bash
hermes plugins enable photon-platform
```

Hermes reported:

```text
✓ Plugin platforms/photon enabled. Takes effect on next session.
```

The important phrase is `Takes effect on next session`.

## Durable lesson

Do not conclude Photon/iMessage is unsupported when the command is missing in the same running session. Plugin-provided CLI subcommands may only be registered after a fresh Hermes CLI process imports the enabled plugin set.

## Normal remediation

1. Enable the plugin:

```bash
hermes plugins enable photon-platform
```

2. Start a new Hermes process/session, then retry:

```bash
hermes photon setup --phone +15551234567
```

3. Verify:

```bash
hermes photon status
hermes gateway status
```

## Diagnostic workaround inside a source checkout

If you must continue without restarting and you are inside the Hermes source checkout, the plugin's `cli.py` can be invoked through the Hermes venv Python. This is a temporary diagnostic path, not the normal user-facing command.

```bash
cd ~/.hermes/hermes-agent
venv/bin/python - <<'PY'
import argparse, sys
from plugins.platforms.photon.cli import register_cli
parser = argparse.ArgumentParser(prog='hermes photon')
register_cli(parser)
args = parser.parse_args(['status'])
sys.exit(args.func(args))
PY
```

For setup without browser auto-open:

```bash
cd ~/.hermes/hermes-agent
venv/bin/python - <<'PY'
import argparse, sys
from plugins.platforms.photon.cli import register_cli
parser = argparse.ArgumentParser(prog='hermes photon')
register_cli(parser)
args = parser.parse_args(['setup', '--no-browser'])
sys.exit(args.func(args))
PY
```

When this starts device login, give the user only the Photon URL, user code, and the exact next input needed. Wait for approval before continuing.

## Avoid saving these as rules

- Do not record `hermes photon` as permanently broken.
- Do not record missing credentials, missing Node modules, or missing phone numbers as durable limitations.
- Capture the fix path: enable the plugin, start a fresh process if needed, then run the status/setup verification.
