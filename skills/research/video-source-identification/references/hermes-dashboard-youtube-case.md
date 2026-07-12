# Representative case: Hermes Agent local dashboard

## User-supplied source

- YouTube URL: `https://youtu.be/6GtF_uHbGhw`
- Resolved video title from public watch-page metadata: `Hermes Agentの全レベルを徹底解説`
- The transcript endpoint was blocked by the cloud-provider IP, so identification used page metadata plus primary Hermes documentation and local CLI help.

## Primary evidence

- Official docs: https://hermes-agent.nousresearch.com/docs/user-guide/features/web-dashboard
- Official docs state that `hermes dashboard` starts a local web server and opens `http://127.0.0.1:9119` in a browser.
- Local CLI verification:

```text
hermes dashboard --help
Launch the Hermes Agent web dashboard for managing config, API keys, and sessions
--port PORT   Port (default 9119, 0 for auto-assign by OS)
--host HOST   Host (default 127.0.0.1)
--no-open     Don't open browser automatically
```

## Identification result

The localhost browser UI in the video is best identified as the Hermes Agent Web Dashboard, not an official Anthropic product named “Claude Code OS”. Keep the distinction explicit: the dashboard is a local management/chat web UI; it is separate from any browser-automation target used by an agent.

## Reusable lesson

When direct video playback or captions are unavailable, verify the suspected local service using the video's public identity, official documentation, and the installed CLI's current `--help` output. Mark frame-level observations as unverified unless the video was actually inspected visually.
