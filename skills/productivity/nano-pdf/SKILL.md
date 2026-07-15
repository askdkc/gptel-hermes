---
requires_tools: [hermes_file_read, hermes_terminal, hermes_terminal_authenticated]
name: nano-pdf
description: "Edit PDF text/typos/titles via nano-pdf CLI (NL prompts)."
version: 1.0.0
author: community
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [PDF, Documents, Editing, NLP, Productivity]
    homepage: https://pypi.org/project/nano-pdf/
---

# nano-pdf

Edit PDFs using natural-language instructions. Point it at a page and describe what to change.

## Prerequisites

```bash
# Install with uv (recommended — already available in Hermes)
uv pip install nano-pdf

# Or with pip
pip install nano-pdf
```

## Usage

```bash
hermes_terminal_authenticated(program="nano-pdf", arguments=["edit", "<file.pdf>", "<page_number>", "<instruction>"], timeout=300)
```

## Examples

```bash
# Change a title on page 1
hermes_terminal_authenticated(program="nano-pdf", arguments=["edit", "deck.pdf", "1", "Change the title to 'Q3 Results' and fix the typo in the subtitle"], timeout=300)

# Update a date on a specific page
hermes_terminal_authenticated(program="nano-pdf", arguments=["edit", "report.pdf", "3", "Update the date from January to February 2026"], timeout=300)

# Fix content
hermes_terminal_authenticated(program="nano-pdf", arguments=["edit", "contract.pdf", "2", "Change the client name from 'Acme Corp' to 'Acme Industries'"], timeout=300)
```

## Notes

- Page numbers may be 0-based or 1-based depending on version — if the edit hits the wrong page, retry with ±1
- Always verify the output PDF after editing with `hermes_terminal`, not the
  text-only file reader. Use `hermes_terminal(program="pdfinfo",
  arguments=["output.pdf"])` and, when size matters, the host's `stat`
  syntax (macOS: `arguments=["-f", "%z", "output.pdf"]`; Linux:
  `arguments=["-c", "%s", "output.pdf"]`).
- The edit command uses an LLM under the hood — requires an API key available to
  the authenticated terminal (check `nano-pdf --help` for config). Use the
  sanitized `hermes_terminal` only for local verification commands below.
- Works well for text changes; complex layout modifications may need a different approach
