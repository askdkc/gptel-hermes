# Japanese PDF font verification checklist

## Preferred font

For Ubuntu/Debian report generation, install `fonts-noto-cjk` and resolve:

```bash
fc-cache -f
fc-match 'Noto Sans CJK JP' -f '%{family}\n%{file}\n'
```

Expected family/file includes `Noto Sans CJK JP` and a file such as `NotoSansCJK-Regular.ttc`.

## CSS

```css
body {
  font-family: "Noto Sans CJK JP", "Noto Sans JP", "Yu Gothic", sans-serif;
}
```

Use a separate CJK mono fallback for code/table identifiers when necessary:

```css
code { font-family: "Noto Sans Mono CJK JP", monospace; }
```

## Artifact checks

1. Render with Chromium `--no-pdf-header-footer`.
2. Confirm `b'%PDF-'` at the start of the file and a non-trivial file size.
3. Inspect `strings report.pdf` for `NotoSansCJKjp-Regular` and `NotoSansCJKjp-Bold` (subsets may be prefixed).
4. Create a screenshot of the source HTML at an A4-like viewport.
5. Inspect the screenshot for `□`, mojibake, clipped Japanese, bad line breaks, and table overflow.

This sequence catches the common failure where the source declares a font that is not installed and Chromium silently substitutes a Latin or low-quality CJK face.
