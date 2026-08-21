# Known issues / follow-ups

Deliberately-deferred items, so they stay visible instead of living in commit messages and
someone's head. Each entry says what is wrong, why it was not fixed at the time, and what fixing
it would involve.

## CLI

### `--report-path` is parsed but never wired to the save path

The CLI accepts `--report-path`, then writes the report to its default location under
`~/Documents/Qalti/Runs/` anyway. Callers have to scrape the run's own `Report saved to:` stdout
line to find it — which is exactly what `scripts/summarize_notes_matrix.py` and the summary block
in `scripts/run_notes_model_matrix.sh` do.

Fix: thread the parsed value through to the report writer, then drop the log-scraping from both
scripts.

### CLI mode force-reports success

CLI runs force the top-level result to success "to match legacy behavior" (`TestRunner.swift`),
so neither the process exit code nor the printed `Test completed successfully` line reflects the
agent's actual verdict. The real verdict is the report JSON's `testResult.test_result`.

This makes the CLI unusable as a CI gate as-is. Fix: return a non-zero exit code on an
agent-judged failure, behind a flag if the legacy behaviour has to be preserved for existing
callers.

## Agent / OpenRouter

### Response sanitization is wired into the streaming path only

`OpenRouterResponseSanitizer` patches OpenRouter responses whose `service_tier` is outside the
vendored client's closed `ServiceTier` enum, or whose `reasoning_details` entry is missing the
field its `type` requires (see `docs/investigations/gemini-decoding-crash.md`). Only
`IOSAgent.ErrorDecodingMiddleware` uses it, via `interceptStreamingData`.

`OpenRouterPointOutService` uses non-streaming `openAI.chats(query:)`, whose `ChatResult` decodes
the same closed enum, and it has its own separate `ErrorDecodingMiddleware` with no sanitization —
so that path can still throw a `DecodingError` on a model that returns an unrecognized tier.

Not observed in practice, which is why it was deferred. The sanitizer is already a standalone,
tested type, so the remaining work is small: call `OpenRouterResponseSanitizer.sanitize(line:)` on
the whole body from that middleware's `intercept(response:request:data:)`. Note the response there
is a bare JSON object rather than an SSE `data:` line, so the sanitizer needs a variant that takes
raw JSON without the prefix.

### Model list has no automated drift check

`TestRunner.AvailableModel` is hand-maintained against a catalogue that changes underneath it, and
a dead ID only surfaces as a 404 at request time. `scripts/check_model_availability.py` can detect
this but nothing runs it on a schedule.

## Runtime

### Qalti GUI spawns an `idb_companion` process every 1-2 seconds

A long-running GUI instance was observed spawning a fresh `idb_companion --list 1` continuously,
accumulating hundreds of CoreSimulator processes and driving load average into the 40s while the
CPU sat mostly idle. This is a device-polling loop with no backoff. See
`docs/investigations/open-app-timeout.md`, finding 4.

Workaround for now: quit the Qalti GUI before running CLI matrices.

### `resolveBundle(for:)` still echoes unresolved input

The lenient `resolveBundle(for:)` is retained for the `DeviceAdministration` call sites, where it
returns its input verbatim on a miss. That is the exact behaviour that turned "app not installed"
into an opaque 60s timeout in `openApp`. The remaining call sites should be migrated to
`resolve(_:)` and the lenient variant deleted.
