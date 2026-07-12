# Web Content Extraction Fallbacks

Captured from session: 20260711 — Fable/Sol/DeepSeek research when Brave API key was set in `.env` but not loaded in running session.

## 1. Brave Search via curl (bypass Hermes `web_search`)

When `web_search` reports `BRAVE_SEARCH_API_KEY is not set` but `.env` has it:

```bash
source ~/.hermes/.env 2>/dev/null
curl -s "https://api.search.brave.com/res/v1/web/search?q=QUERY&count=10" \
  -H "Accept: application/json" -H "Accept-Encoding: gzip" \
  -H "X-Subscription-Token: $BRAVE_SEARCH_API_KEY" \
  | gunzip 2>/dev/null \
  | python3 -c "
import json,sys
d = json.load(sys.stdin)
for r in d.get('web',{}).get('results',[]):
    print(f\"{r['title']}\\n  {r['url']}\\n  {r.get('description','')}\\n\")
"
```

Key: `source ~/.hermes/.env` loads API key into shell. The `.env` file is NOT automatically sourced for every `terminal()` call — must be explicit.

## 2. Jina AI Reader for JS-rendered pages

When `web_extract` fails (Brave is search-only, or page is JS-rendered SPA):

```bash
curl -sL "https://r.jina.ai/URL" \
  -H "Accept: text/markdown" \
  -H "User-Agent: Mozilla/5.0" \
  | head -300
```

- Free, no auth
- Works for React/Next.js docs, Vercel-deployed apps
- Returns clean markdown
- 429 = rate limit, retry after delay
- Vercel Security Checkpoint page = also rate limited

## 3. Raw HTML extraction from non-JS pages

When page is server-rendered but extraction fails:

```bash
curl -sL "URL" -H "User-Agent: Mozilla/5.0" | python3 -c "
import sys, re
html = sys.stdin.read()
text = re.sub(r'<script[^>]*>.*?</script>', '', html, flags=re.DOTALL)
text = re.sub(r'<style[^>]*>.*?</style>', '', text, flags=re.DOTALL)
text = re.sub(r'<[^>]+>', '\n', text)
text = re.sub(r'\n{3,}', '\n\n', text)
text = re.sub(r'[ \t]+', ' ', text)
print(text[:8000])
"
```

## Priority order

1. `web_search` + `web_extract` (Hermes tools) — always try first
2. Jina reader (`r.jina.ai`) — JS-rendered pages, markdown output
3. Brave API via curl — when `web_search` key isn't loaded in session
4. Raw HTML via curl — simple server-rendered pages
