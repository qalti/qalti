# OpenRouter model IDs used by Qalti

`TestRunner.AvailableModel` (`xcodeproject/Qalti/Services/Agent/TestRunner.swift`) hardcodes the
OpenRouter model IDs Qalti's agent can drive. OpenRouter's catalogue changes over time — models
get renamed, superseded, or removed — so this list can silently go stale: picking a dead ID in the
UI/CLI produces a live 404 from OpenRouter at request time, not a build-time or startup failure.

## Known-stale IDs (kept in the enum, not removed)

As of 2026-07-31, two IDs in the enum are confirmed **dead** (hard 404 from OpenRouter):

| Case | Dead ID | Live replacement | Case for replacement |
|---|---|---|---|
| `grok4` | `x-ai/grok-4` | `x-ai/grok-4.5` | `grok45` |
| `gemini3proPreview` | `google/gemini-3-pro-preview` | `google/gemini-3.1-pro-preview` | `gemini31proPreview` |

The dead cases are intentionally left in place rather than repointed or removed, so that a stale
ID stays a reproducible, documented example rather than silently disappearing — the replacement
cases were added alongside them instead. If you're touching this list, prefer removing the dead
entries once you've confirmed nothing depends on the specific error behavior of picking one.

## Other models in the enum confirmed live (as of the same check)

`gpt-4.1`, `gemini-2.5-pro`, `claude-sonnet-4`, `gpt-5-mini`, `gpt-5`, `gpt-5-nano`,
`claude-haiku-4.5`, `gemini-3-flash-preview`, `gemini-3-pro-image-preview`.

## How to re-verify

The catalogue drifts, so treat any date above as a snapshot, not a guarantee. To re-check:

```bash
source .venv/bin/activate  # after `make venv`
export OPENROUTER_API_KEY=...
python scripts/update_open_router_models.py   # fetches the live catalogue, no key needed
python scripts/check_model_availability.py scripts/output/openrouter_suitable_models_<timestamp>.json
```

Or run the full model matrix (`scripts/run_notes_model_matrix.sh` — see its header comment) against
`tests/reminders_create_and_verify.test` to exercise every ID in `TestRunner.AvailableModel`
end-to-end, not just check catalogue presence.

## Related known issues (separate from stale IDs)

Both of the issues below are **fixed** on this branch; they are listed because they were failures
of a *live* model ID, which is easy to misread as the ID itself having gone stale.

- `gemini-2.5-pro` and `gemini-3-flash-preview` crashed Qalti's response decoding entirely
  (unrelated to whether the ID was live). Fixed by streaming-chunk sanitization — see
  `docs/investigations/gemini-decoding-crash.md`.
- `gpt-5-nano` silently exhausted all 50 iterations returning empty content. Root-caused to
  Qalti's own `maxCompletionTokens` budget being too tight for a reasoning model, not to the
  model or the ID — see `docs/investigations/gpt5-nano-flakiness.md`.
