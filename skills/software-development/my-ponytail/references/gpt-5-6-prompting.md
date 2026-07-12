# GPT-5.6 Prompting Notes

Source: OpenAI, [Model guidance](https://developers.openai.com/api/docs/guides/latest-model?model=gpt-5.6), consulted 2026-07-12.

## Durable guidance for Ponytail

- Prefer lean prompts: remove repeated instructions, unnecessary examples, and overly detailed tool descriptions.
- State each instruction once. Keep style guidance only when it encodes a product requirement or fixes a measured failure.
- Define autonomy and approval boundaries in one place. Name safe local actions explicitly, and distinguish external, destructive, costly, or scope-expanding actions.
- GPT-5.6 is concise by default. Use the API's `text.verbosity` for a default response-detail level, then specify task-specific required content in the prompt.
- For short answers, define what must be preserved: conclusion, supporting evidence, material caveat, and next action. Do not use a line count as a substitute for content priorities.
- Evaluate prompt reductions on representative tasks. OpenAI reports directional internal coding-agent results where leaner system prompts improved evaluation scores by roughly 10–15% while reducing tokens and cost; these figures are not a guarantee for another workload.

## Application rule

Ponytail should enforce engineering decisions—scope, reuse, root-cause fixes, and verification—without forcing `Code first`, a fixed line count, or a status banner on every response. User-requested reports, walkthroughs, and detailed design notes take precedence over the default concise style.
