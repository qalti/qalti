# OpenRouter model IDs used by Qalti

`TestRunner.AvailableModel` (`xcodeproject/Qalti/Services/Agent/TestRunner.swift`) hardcodes the
OpenRouter model IDs Qalti's agent can drive. OpenRouter's catalogue changes over time — models
get renamed, superseded, or removed — so this list can silently go stale: picking a dead ID in the
UI/CLI produces a live 404 from OpenRouter at request time, not a build-time or startup failure.

## Retired IDs (removed 2026-07-31)

Two IDs were confirmed **dead** (hard 404 from OpenRouter) and have been removed from the enum,
along with their aliases, in favour of live replacements:

| Removed case | Dead ID | Replaced by | New case |
| --- | --- | --- | --- |
| `grok4` | `x-ai/grok-4` | `x-ai/grok-4.5` | `grok45` |
| `gemini3proPreview` | `google/gemini-3-pro-preview` | `google/gemini-3.1-pro-preview` | `gemini31proPreview` |

Retiring an ID is a small breaking change, handled as follows:

- **CLI:** `--model x-ai/grok-4` (or the `grok-4` / `grok 4` aliases) now **fails** with an error
  listing the available models. It deliberately does not fall back to a default, and it does not
  silently redirect to the replacement — either would report a result for a model that never ran.
- **App:** a retired ID saved in `UserDefaults` no longer resolves, so the picker falls back to its
  default. Nothing crashes and the selection is visible in the UI.

Aliases for a retired ID are removed rather than repointed at the replacement, for the same reason:
`grok-4` and `grok-4.5` are different models, and a run labelled with the wrong one is worse than a
run that refuses to start.

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
