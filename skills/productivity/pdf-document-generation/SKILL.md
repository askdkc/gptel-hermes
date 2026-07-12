---
name: pdf-document-generation
description: "Generate polished PDFs from HTML or structured content with reliable Japanese typography, embedded fonts, and visual verification."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [pdf, japanese, fonts, html, chromium, documents, verification]
---

# PDF document generation

Use for creating or regenerating a PDF deliverable, especially Japanese reports where typography, line wrapping, font embedding, and legibility matter.

## Workflow

1. **Choose the simplest source format.** For a report with tables and links, use self-contained HTML + CSS and the native/headless Chromium print-to-PDF path. Avoid adding a PDF library unless the layout requires programmatic drawing.
2. **Install a real Japanese font before rendering.** On Debian/Ubuntu, prefer `fonts-noto-cjk`; Noto Sans CJK JP is a clean general-purpose sans-serif choice. Verify resolution with `fc-match 'Noto Sans CJK JP'`.
3. **Declare explicit font fallbacks.** Use a CSS stack beginning with `"Noto Sans CJK JP"`, then platform Japanese fonts, then a generic sans-serif. Use a CJK monospace face for code only if needed.
4. **Render without browser headers/footers.** Use Chromium headless with `--no-pdf-header-footer`; set page size and margins in `@page`. Do not add generated-at or filename headers/footers unless explicitly requested.
5. **Verify the artifact, not only the source.** Check Chromium exit status, PDF signature/size, page count, and embedded font names. Take a rendered screenshot and inspect for Japanese tofu boxes, mojibake, bad fallback, clipped text, or table overflow.
6. **Deliver the regenerated PDF.** Keep the HTML source beside the PDF when useful for future edits, but send the PDF as the primary artifact.

## Known-good commands (Linux)

```bash
sudo apt-get install -y fonts-noto-cjk
fc-cache -f
fc-match 'Noto Sans CJK JP' -f '%{family}\\n%{file}\\n'
chromium --headless --no-sandbox --disable-gpu \
  --print-to-pdf=report.pdf --no-pdf-header-footer file:///absolute/path/report.html
strings report.pdf | grep -E 'Noto|CJK|IPA|WenQuan' | head
```

For a visual check:

```bash
chromium --headless --no-sandbox --disable-gpu \
  --window-size=1240,1754 --screenshot=report-preview.png \
  file:///absolute/path/report.html
```

## Quality rules

- Never claim Japanese PDF quality from HTML inspection alone; inspect the rendered PDF or screenshot.
- Prefer font embedding/subsetting visible in the PDF font table; a system font being installed is not enough.
- If the font package is unavailable, use an existing Japanese font only after checking `fc-list :lang=ja`; do not silently fall back to a Latin-only font.
- Keep document typography consistent: one body font, explicit heading hierarchy, readable table size, and adequate A4 margins.
- Do not fabricate missing source data merely to fill a report; mark blocked pages or unverified prices explicitly.

## References

See `references/japanese-font-verification.md` for the reusable font-selection and verification checklist.

## Pitfalls

- `font-family: "Noto Sans CJK JP"` without installing the font causes Chromium to silently choose an inferior fallback.
- A successful Chromium exit code does not prove the PDF is legible; inspect embedded fonts and a screenshot.
- `pdfinfo`/`pdftotext` may not be installed in minimal environments; use PDF signature, object/font strings, and Chromium screenshots as a dependency-light fallback.
- Do not confuse a PDF editing skill with a PDF generation workflow: natural-language editing tools are unnecessary when regenerating the source HTML is deterministic and available.
