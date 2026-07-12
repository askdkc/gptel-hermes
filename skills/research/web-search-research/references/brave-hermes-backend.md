# Brave Search API in Hermes: verified notes

## Observed configuration

```yaml
web:
  backend: brave-free
```

```env
BRAVE_SEARCH_API_KEY=<set; never print the value>
```

The Hermes implementation treats `brave-free` as a built-in backend and checks `BRAVE_SEARCH_API_KEY` for availability. The backend name is intentionally `brave-free`; it is not evidence that the API key is unused. In the current Hermes source, the built-in backend list includes `brave-free` rather than a separate ordinary `brave` backend.

## Capability boundary

Hermes documents Brave Search (free tier) as:

- search: supported
- extraction: unsupported
- free allowance: documented as 2,000 queries/month (confirm current provider terms before relying on the number)

Therefore, `web_search` can discover URLs and snippets, while `web_extract` needs a separate extraction-capable backend or a direct source API/browser retrieval.

## Minimal safe verification

1. Read `hermes config path` and `hermes config env-path`.
2. Confirm `web.backend` without printing secrets.
3. Confirm `BRAVE_SEARCH_API_KEY` is present by printing only `present/missing`.
4. Make one minimal Brave request and report only HTTP status/result count.
5. Restart the Hermes gateway or start a new session after changing `.env`.

## Research implication

For user-sentiment research, use Brave for broad discovery, then verify representative Reddit/GitHub/official pages through direct APIs or extraction. Report when findings are snippet-only and separate vendor marketing from firsthand user reports.
