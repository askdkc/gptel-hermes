---
name: image-generation-and-editing
description: "Generate or edit images with clear language, source fidelity, and native file delivery."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [image-generation, image-editing, upscaling, Japanese-text, media-delivery]
---

# Image Generation and Editing

Use for text-to-image generation, image-to-image edits, cleanup, restoration, upscaling, and meme/infographic artwork.

## Workflow

1. **Identify the operation**
   - New artwork: use text-to-image.
   - Existing image: pass the source image and describe only the intended changes.
   - Cleanup/upscale: explicitly preserve composition, wording, and layout; request denoising, sharpening, and artifact removal.
2. **Match the user's language**
   - If the user asks in Japanese, make the generated labels and prompt Japanese.
   - Put required text in quotes and state that wording must be exact.
   - For dense Japanese text, prefer fewer, larger labels over many small labels.
3. **Preserve source fidelity for edits**
   - State what must not change: composition, characters, arrows, colors, text, and aspect ratio.
   - For restoration, prohibit new logos, watermarks, decorations, or rewritten text.
4. **Generate immediately** with the image-generation tool; do not ask unnecessary design questions when the user's intent is clear.
5. **Deliver the actual artifact** using `MEDIA:/absolute/path/to/file`.

## Meme and infographic defaults

- For cycles, use `circular-flow` structure: a dominant loop, thick directional arrows, and a central concept.
- For humorous explanatory art, `craft-handmade` or rough marker style is a good default.
- Keep labels large and legible; request a clean background and limited accent colors.
- Avoid adding English labels when the user requested Japanese.

## Verification checklist

- Confirm the image-generation tool returned a real path or URL.
- For edits, check that the output is an image artifact and not merely a description.
- Deliver the returned path verbatim; do not invent filenames.

## Pitfalls

- A first generation may use the wrong language or garble dense text. If the user corrects the language, regenerate rather than defending the result.
- Image models can alter text during upscaling. Explicitly demand exact text preservation; if exact typography is critical, use a deterministic image-editing/typesetting workflow instead of relying solely on generative restoration.
- Do not claim an image is clean or faithful without producing the edited artifact.

See `references/session-patterns.md` for a compact record of proven prompt patterns.