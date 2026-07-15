---
requires_tools: [hermes_terminal]
name: model-catalog-comparison
description: Compare AI model catalogs using authoritative live metadata, pricing, capability positioning, and honest performance evidence; produce compact decision tables and performance-versus-cost diagrams.
---

# AI model catalog comparison

Use when the user asks to compare named AI models, model tiers, pricing, benchmarks, or performance-versus-cost trade-offs.

## Workflow

1. **Identify the catalog and exact IDs first.** Model nicknames are ambiguous. Search the relevant provider/catalog API or official model index and resolve names to canonical IDs. Do not assume that a name refers to a public model. Use an available web-search integration for discovery when present; otherwise retrieve the official catalog directly through the terminal.
2. **Prefer live authoritative metadata.** Read pricing, context length, modalities, output limits, descriptions, and capability notes from the provider's model endpoint or official docs. Record the retrieval date when the catalog is dynamic.
3. **Separate evidence types.** Distinguish:
   - measured benchmark scores (with benchmark name, version, and source),
   - provider positioning/marketing descriptions,
   - agent-observed qualitative impressions.
   Never turn a tier label into an invented numeric benchmark.
4. **Check whether variants are distinct models.** A `pro`, `reasoning`, or `high` suffix may be a serving/reasoning mode over the same underlying model. Compare quality, latency, and cost implications without claiming a new base model.
5. **Normalize costs.** Report input and output separately, normally per 1M tokens. If useful, calculate a representative workload, but state the input/output token assumptions. Include cache and tool-call charges when relevant.
6. **Make the decision legible.** Use a compact table plus a simple 2-axis diagram or ordered frontier. State the recommended model by workload: high-volume/simple, balanced, and complex reasoning/coding.
7. **Link every dynamic claim.** Include direct provider/model pages and the raw catalog endpoint where possible. If benchmark data is unavailable, say so explicitly and label the chart as qualitative.

## Output rules

- Start with the resolved model family and canonical IDs.
- Use Japanese when the user prefers Japanese; keep model IDs and API fields unchanged.
- Favor a concise table and a small ASCII/Markdown diagram over a long essay.
- Explain what is skipped when data is unavailable: e.g. "公開ベンチマークなし; tier positioning only."
- Do not fabricate latency, quality scores, token limits, or benchmark results.

## Provider/API evidence workflow

- Resolve canonical IDs from a live catalog before comparing display names. For OpenRouter, query `https://openrouter.ai/api/v1/models` directly and retain `id`, `pricing`, `context_length`, and retrieval time.
- If the configured web-search/extraction backend is unavailable, use direct HTTPS retrieval with the standard library or `requests`; do not repeatedly retry the same failed backend. Prefer official HTML/JSON endpoints and cite the exact URL.
- Treat subscription pricing and API pricing as separate products. A ChatGPT/Claude/Z.AI/Ollama plan may not authorize arbitrary API calls from Hermes, and an API key may not include the consumer app's quota.
- For dynamic JavaScript pages, extract server-rendered metadata or an official documentation route; if a page is blocked (for example, a challenge/403), record the limitation and do not fill the gap from memory or snippets.
- Normalize API prices to $/1M input and output tokens separately. Include a clearly stated representative workload and exclude or separately model cache, web-search, tool-call, batch, and priority charges.
- Distinguish provider marketing claims (for example, “coding/agents” or “rival Opus”) from measured benchmark results. If an apples-to-apples benchmark cannot be verified for the current model generation, provide qualitative workload guidance only.

## Decision rules for Hermes / 24-hour operation

- Separate the recommendation into: (1) cheapest fixed subscription, (2) cheapest unrestricted/programmable API, (3) cheapest local option, and (4) quality-first option. This avoids declaring a consumer subscription the universal winner.
- Evaluate agent quotas: rolling 5-hour limits, weekly limits, concurrency, supported tools, model switching, context size, and whether arbitrary OpenAI-compatible requests are allowed.
- Use a routing recommendation for cost control: low-cost model for cron/monitoring/routine edits, stronger model for difficult debugging/design, while retaining approval/sandbox/security controls.
- Record model deprecation dates and migration IDs when official docs expose them; stale aliases can invalidate a cost comparison.

## Pitfalls

- Searching only exact display names can miss canonical IDs; inspect the provider's model catalog.
- Search snippets are not sufficient evidence for current prices.
- Equal pricing between base and Pro variants does not prove equal latency or total cost: pro reasoning may consume more time/tokens.
- A qualitative performance ranking is not an independent benchmark. Label it clearly.
- Do not infer an exact tier price from a phrase such as “from $18/month”; report only the verified starting price unless the plan table is accessible.
- Do not call a plan “unlimited” without documenting rolling-window, weekly, concurrency, model, or tool restrictions.
- If the names cannot be resolved to one provider, ask for the provider/platform or source URL instead of comparing unrelated models.

## Reference material

- Session-specific OpenRouter GPT-5.6 Sol/Terra/Luna evidence and normalized pricing: `references/openrouter-gpt56-sol-terra-luna.md`
- Live-provider research and Hermes/24-hour decision checklist: `references/live-provider-research.md`

## Reference material

- Session-specific OpenRouter GPT-5.6 Sol/Terra/Luna evidence and normalized pricing: `references/openrouter-gpt56-sol-terra-luna.md`
