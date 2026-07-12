# Live provider research notes: Hermes + 24-hour operation

Session evidence pattern (retrieved 2026-07-12 JST; prices are dynamic and must be rechecked):

## Direct authoritative endpoints

- OpenRouter model catalog: `https://openrouter.ai/api/v1/models`
  - Read `data[].id`, `pricing.prompt`, `pricing.completion`, `pricing.input_cache_read`, `context_length`.
  - Values are dollars per token; multiply by 1,000,000 for $/1M tokens.
- OpenAI API pricing: `https://platform.openai.com/docs/pricing`
- Anthropic consumer/API pricing: `https://claude.com/pricing`
- DeepSeek API docs: `https://api-docs.deepseek.com/quick_start/pricing`
- Z.AI Coding Plan overview/FAQ: `https://docs.z.ai/devpack/overview`, `https://docs.z.ai/devpack/faq`
- Ollama pricing: `https://ollama.com/pricing`

## Observed facts to verify afresh

- OpenRouter exposed current canonical families including `deepseek/deepseek-v4-flash`, `deepseek/deepseek-v4-pro`, `z-ai/glm-5.2`, `z-ai/glm-4.7-flash`, OpenAI GPT-5.6 variants, and Claude Sonnet variants.
- Z.AI's public metadata states Coding Plan starts at $18/month, supports GLM-5.2, GLM-5-Turbo, and GLM-4.7, and documents approximate rolling/weekly prompt caps: Lite ~80 prompts/5h and ~400/week; Pro ~400/5h and ~2,000/week; Max ~1,600/5h and ~8,000/week. These are estimates, not guaranteed token quotas; prompts may invoke 15–20 model calls and model weighting varies.
- Ollama pricing states Free for local execution, Pro $20/month or $200/year, Max $100/month. Cloud usage is measured by utilization and has 5-hour and weekly limits; local execution is unlimited subject to hardware.
- Anthropic's current pricing page exposed Claude Pro at $20 monthly or $17/month equivalent annually, Max from $100/month, and API model prices separately. Do not merge these accounts with Hermes API costs.
- DeepSeek docs exposed V4 Flash/Pro and stated old `deepseek-chat`/`deepseek-reasoner` aliases are scheduled for deprecation on 2026-07-24 15:59 UTC. Always capture migration dates.

## Cost example method

For a representative workload of 10M input + 3M output tokens/month:

`monthly_cost = 10 * input_price_per_1M + 3 * output_price_per_1M`

State that cache reads/writes, tool calls, web search, batch/priority multipliers, retries, and context overhead are excluded unless explicitly modeled. The example is for comparison, not a usage forecast.

## Recommendation structure

Report four winners separately:

1. Cheapest fixed subscription for coding-agent use.
2. Cheapest programmable API for Hermes and arbitrary routing.
3. Cheapest local option when hardware already exists.
4. Quality-first option with its higher cost and rate-limit tradeoff.

Never call the overall winner without specifying which of these four meanings is intended.

## Failure-handling lesson

If web search/extraction is unavailable, switch once to direct HTTPS/JSON/HTML retrieval and record blocked pages (e.g. Cloudflare 403). Do not invent a blocked subscription price or retry the same backend in a loop.
