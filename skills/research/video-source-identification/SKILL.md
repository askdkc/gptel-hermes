---
requires_tools: [hermes_terminal]
name: video-source-identification
description: Identify software, services, and workflows shown in user-supplied videos, especially when transcripts or direct playback are unavailable.
version: 1.0.0
license: MIT
metadata:
  hermes:
    tags: [video, youtube, source-identification, software-identification, research]
---

# Video source identification

Use when a user shares a video and asks what software, service, UI, or local web application appears in it.

## Workflow

1. **Resolve the video identity first.** Extract the video ID, title, channel, duration, and available description/metadata from the public video page. Use optional web-search, web-extraction, or browser integrations for discovery when available; otherwise fetch the public page directly through the terminal. Do not infer the product from the URL alone.
2. **Try the transcript path.** Use the installed YouTube transcript helper or `youtube_transcript_api`. If the request is blocked by a cloud-provider IP, do not repeatedly retry or claim the transcript is disabled.
3. **Fallback to page metadata.** Parse the YouTube watch page for `videoDetails`, title, description, chapters, captions, and related links. Search the exact title plus distinctive UI terms when needed.
4. **Correlate with authoritative product documentation.** For a suspected product, inspect its official docs, CLI help, repository, or source page. Verify the exact command, default host/port, and whether the UI opens a browser.
5. **Separate identification levels.** Report what is certain, what is likely, and what remains unverified. A video may show a community project with a similar name to an official product.
6. **Answer the user's concrete question first.** If they ask whether a browser/local service was present, state the likely service and the evidence, then distinguish it from similarly named products.

## Verification checklist

- Video title/channel matches the user's link.
- Product/service name appears in an authoritative source.
- Local URL and default port come from official docs or live CLI help.
- `--help` output is preferred over stale blog posts for current flags.
- If direct visual inspection was not possible, say so; do not claim frame-level certainty.

## Fallback patterns

- Transcript blocked: use public HTML metadata, search the exact title, and inspect official docs.
- Browser automation unavailable: use direct HTTP fetches and local CLI help; do not fabricate a visual observation.
- Similar names: distinguish official service, open-source repository, and user-created configuration/OS projects.

## Pitfalls

- “OS” may be a community project name rather than a vendor service.
- A browser window can be the product's management dashboard, not the agent's browser-automation target.
- A localhost port in a demo is not evidence of a hosted SaaS endpoint.
- Search snippets are discovery evidence; verify the final claim against primary documentation.

## References

See `references/hermes-dashboard-youtube-case.md` for the Hermes Dashboard identification pattern and source URLs from a representative investigation.
