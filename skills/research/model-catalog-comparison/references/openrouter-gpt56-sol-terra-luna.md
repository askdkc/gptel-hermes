# OpenRouter GPT-5.6 Sol / Terra / Luna (session evidence)

Source inspected: `https://openrouter.ai/api/v1/models`.

Canonical IDs and live catalog data observed in this session:

| ID | Input $/1M | Output $/1M | Context | Catalog positioning |
|---|---:|---:|---:|---|
| `openai/gpt-5.6-luna` | 1 | 6 | 1,050,000 | Fast, cost-efficient; high-volume, latency-sensitive chat/classification/light agent workflows |
| `openai/gpt-5.6-luna-pro` | 1 | 6 | 1,050,000 | Same underlying Luna; served with `reasoning.mode=pro` for higher-quality complex-task responses |
| `openai/gpt-5.6-terra` | 2.5 | 15 | 1,050,000 | Balanced; everyday coding, reasoning, and agentic work; between Luna and Sol |
| `openai/gpt-5.6-terra-pro` | 2.5 | 15 | 1,050,000 | Same underlying Terra; `reasoning.mode=pro` |
| `openai/gpt-5.6-sol` | 5 | 30 | 1,050,000 | Flagship; complex reasoning, coding, agentic workflows; particularly strong for CLI and multi-step coding |
| `openai/gpt-5.6-sol-pro` | 5 | 30 | 1,050,000 | Same underlying Sol; `reasoning.mode=pro` |

All six showed maximum completion tokens of 128,000 in `top_provider`. Web search pricing was `$0.01` per request in the catalog. Cache prices were proportional to the base input price.

Important evidence boundary: the catalog supplied qualitative positioning and prices, but no independent MMLU/SWE-bench/etc. scores. A Sol > Terra > Luna performance diagram is therefore a provider-positioning visualization, not a measured benchmark chart. Pro variants had the same listed token prices as their base variants; latency and actual reasoning-token consumption were not established by this lookup.

Useful pages:
- Raw catalog: https://openrouter.ai/api/v1/models
- Sol: https://openrouter.ai/openai/gpt-5.6-sol
- Terra: https://openrouter.ai/openai/gpt-5.6-terra
- Luna: https://openrouter.ai/openai/gpt-5.6-luna
- OpenAI reasoning modes: https://developers.openai.com/api/docs/guides/reasoning#reasoning-mode
