# Investigation: `gpt-5-nano` intermittently burns all 50 iterations silently

## Status: FIXED AND VERIFIED 2026-07-31

Applied the hypothesis fix below and re-ran 3 fresh reps against the same fixture, same clean
environment: **3/3 passed**, each in 67-100s (vs. the pre-fix 2/3 failure rate at ~1080s/hang
each). Real verdicts confirmed via each run's `testResult.test_result`
(`"pass with comments"`, `"pass"`, `"pass"`), not just clean CLI exit codes.

Changes made:

- `IOSAgent.swift` (`prepareQuery`): `maxCompletionTokens` raised from a flat `1000` to `4000`
  for all models — reasoning-capable models draw hidden reasoning tokens from this same budget,
  not a separate one, so too tight a cap can leave zero tokens for the visible answer.
- `TestRunner.swift` (`AvailableModel.reasoning`): `gpt5nano` now explicitly gets `.low`
  reasoning effort, same treatment as `gpt5`, instead of `nil` (which likely let OpenRouter/the
  provider default to a more expensive effort level with nothing constraining hidden-token spend).

This resolves the "is it my Mac or the model" question definitively: it was neither, in the
narrow sense — it was Qalti's own fixed request configuration not giving a small reasoning model
enough room to think *and* answer within the same budget. Below is kept as the original
investigation trail for context.

## Status (superseded): ROOT CAUSE CONFIRMED 2026-07-31, fix not yet applied

Ran 3 fresh reps against the Reminders fixture with `--log-level debug`, in a deliberately clean
environment (single simulator, the stale Qalti GUI instance that was found spawning a runaway
`idb_companion` loop was quit first) — ruling out "it's a local machine issue" as the cause, per
the user's own suspicion going in. Result: **2 of 3 reps failed identically** (rep 1: pass in
189s; rep 2 and rep 3: failed after ~1080s each, hitting the 50-iteration cap).

The debug logs still only showed `"No tool calls in assistant response"` /
`"No JSON found, asking for JSON or to continue test execution"` on repeat, without the actual
content — but pulling the failing runs' saved report JSON (`runHistory`) directly revealed the
real mechanism: **the assistant's message content was a literal empty string (`""`) on every one
of the last many turns**, not malformed text or a misunderstanding of the prompt. Once nano starts
returning empty content, it never recovers, despite being re-prompted every iteration.

**Leading hypothesis, not yet tested:** `IOSAgent.prepareQuery` sets a fixed
`maxCompletionTokens: 1000` (`IOSAgent.swift:575`), and `TestRunner.AvailableModel.gpt5nano` gets
no explicit `reasoning` effort (only `.gpt5` sets `.low` — see the `reasoning` computed property).
For a small reasoning-capable model, it's plausible nano is spending its entire completion-token
budget on hidden reasoning tokens under some condition, leaving nothing for visible output. This
would explain empty content that never self-corrects. **Not yet confirmed** — would need either
(a) explicitly setting a low/none reasoning effort for `gpt5nano` and re-testing, or (b) raising
`maxCompletionTokens` for this model and re-testing, or (c) checking whether OpenRouter's response
exposes reasoning-token usage separately to confirm the budget really is being consumed that way.

The rest of this document is kept as the original hypothesis-stage investigation for context.

## Context / how this was found

Branch: `feature/openrouter_model_tooling`. Found during the same 10-model matrix effort as the
(already-fixed) `open_app` timeout bug and the (documented, not-yet-fixed) Gemini decoding
crashes — see `docs/investigations/open-app-timeout.md` and `docs/investigations/gemini-decoding-crash.md`.
`gpt-5-nano` is unrelated to either of those; it's its own distinct issue.

Two real matrix runs exist on disk with `gpt-5-nano` results, both against the Reminders fixture:

- `scripts/output/notes_model_matrix_20260729_144842/gpt-5-nano.log` — **passed**, completed
  cleanly in ~9 minutes across 20 logged iterations (open Reminders → dismiss iCloud prompt → tap
  add → type text → tap save).
- `scripts/output/notes_model_matrix_20260729_203638/gpt-5-nano.log` — **failed**, but not in an
  informative way: it opened Reminders successfully at iteration #03, then produced **zero**
  further log output for ~25 minutes before hitting `"Max iterations reached without completion
  or valid JSON result"` and exiting with `Test failed: Received unexpected response from AI
  service`.

Same model, same fixture, same test, wildly different outcome. This doc is a **root-cause
hypothesis backed by code reading**, not a confirmed fix — the actual behavior during the silent
25-minute gap has not yet been directly observed (see "What's still unconfirmed" below).

## Exact symptom (log excerpts)

Passing run (`notes_model_matrix_20260729_144842/gpt-5-nano.log`), for contrast:
```
[14:55:38.0-INF-IOSAgent] AWS S3 credentials missing; using base64 screenshots
[14:55:49.4-INF-IOSAgent] Tool calls rejected: Agent did not provide a comment before calling the tool
[14:55:53.7-INF-IOSAgent] Agent Iteration #02/50: open_app(app_name="Reminders")
[14:58:19.9-INF-IOSAgent] Agent Iteration #08/50: tap(element_name="Add reminder button...")
[15:00:32.4-INF-IOSAgent] Agent Iteration #14/50: input(text="Qalti smoke test reminder")
[15:03:08.0-INF-IOSAgent] Agent Iteration #20/50: tap(element_name="Blue checkmark button...")
[15:04:32.1-INF-CLI] Test completed successfully.
```
Note it *did* hit the "no comment provided" rejection once early on (iteration ~1) and recovered
fine — this rejection path is a normal, survivable occurrence, not itself the bug.

Failing run (`notes_model_matrix_20260729_203638/gpt-5-nano.log`), reproduced in full except
timestamps-only lines:
```
[20:45:55.9-INF-IOSAgent] AWS S3 credentials missing; using base64 screenshots
[20:46:38.2-INF-IOSAgent] Agent Iteration #03/50:
    Qalti Action: open_app(app_name="Reminders")
[21:11:29.9-WRN-IOSAgent] Max iterations reached without completion or valid JSON result
[21:11:30.0-ERR-ErrorCapturerService] Captured error: Received unexpected response from AI service
[21:11:30.8-INF-RunnerManager] Stopping runner xcodebuild process
[21:11:30.8-ERR-CLI] Test failed: Received unexpected response from AI service
```
That's the **entire** log between 20:46:38 and 21:11:29 — a 24-minute-51-second gap with no INF,
WRN, or ERR lines at all, spanning what must have been ~47 loop iterations (iteration #03 to
somewhere near #50). No "Tool calls rejected" message (which IS logged at `.info`, confirmed
below), no retry messages, no errors — genuinely nothing, until the final give-up.

**Also notable: no report JSON was saved for this failed run** (no "Report saved to:" line
anywhere in the log) — unlike every other failure mode seen in this codebase, which either goes
through `TestRunner`'s forced-success override (still producing a report — see
`docs/follow-ups.md`, "CLI mode force-reports success") or a hard error that still gets logged via a caught path. This
specific failure (`Error.unexpectedResponse` thrown from the bottom of the iteration loop) appears
to skip report-saving entirely, meaning **this failure mode currently leaves zero forensic
artifact beyond whatever the CLI's own stdout log happened to capture**.

## Root-cause hypothesis (from code reading, not yet directly observed)

`IOSAgent.swift:220-297` is the per-test iteration loop. The critical branch:
```swift
// IOSAgent.swift:220-250
for iteration in 0..<maxIterations {
    ...
    let streamed = try streamWithRetries(...)

    guard streamed.toolCalls.isEmpty == false else {
        logger.debug("No tool calls in assistant response")              // DBG — invisible at --log-level info
        if containsValidJSON(streamed.assistantContent) {
            logger.debug("Found valid JSON in assistant response")        // DBG
            ...
            break   // only exit point that produces a final result
        } else {
            logger.debug("No JSON found, asking for JSON or to continue test execution")  // DBG
            ...
            runHistory.append(.user(.init(content: .string(try Prompts.jsonContinuationPrompt()))))
            continue   // <-- loops again completely silently at info level
        }
    }
    ...
    // The "Agent Iteration #X/Y" INF line is only printed via logPlannedAction,
    // called from inside runToolCalls (line 267-275) — i.e. ONLY when the model's
    // response actually contained at least one tool call that also passed the
    // comment-length check.
}
```
The "Tool calls rejected: Agent did not provide a comment" message is confirmed to log at
`.info` (`IOSAgent.swift:691`, inside `shouldRejectToolCallsWithoutComment`) — since it does
**not** appear anywhere in the failing run's log, that specific rejection path can be ruled out
as the cause of the silent gap.

That leaves the `toolCalls.isEmpty == true` branch (lines 234-250) as the only remaining path that
loops (`continue`) without producing any `.info`-or-above log line. **Working hypothesis:**
`gpt-5-nano`, after successfully opening Reminders, started producing responses that contained
neither a tool call nor valid extractable JSON (e.g. plain conversational text, or malformed
JSON that `containsValidJSON`/`extractJSON` didn't accept) — and kept doing so for ~47 consecutive
iterations despite being re-prompted each time with `Prompts.jsonContinuationPrompt()` asking it
to either continue the test or provide the final JSON. This is a **plausible per-model weakness**
for a very small/fast model like nano (worse instruction-following than the mini/full-size
siblings that all passed cleanly in the same matrix), but it's also possible something more
specific is going on (repeating the exact same non-actionable text every time; a subtly broken
prompt continuation that doesn't actually change what's sent; etc.) — **not yet confirmed either
way**, since no debug-level capture of this exists.

## What's still unconfirmed

- **The actual content of `gpt-5-nano`'s responses during the 47 silent iterations.** Not
  captured at `--log-level info` (used by `scripts/run_notes_model_matrix.sh:59`). Need a rerun
  with `--log-level debug` to see the real assistant text each iteration — this would either
  confirm the "stuck rambling / never produces JSON or a tool call" hypothesis, or reveal
  something else entirely (e.g. a decode-adjacent issue like the Gemini bugs, an infinite retry
  in `streamWithRetries` that doesn't log at info either, or something in `containsValidJSON`
  rejecting output that's actually close to valid).
- **Whether this is reproducible/how often.** Only one clean pass and one failure observed so
  far — insufficient sample size to know if this is "sometimes flaky" or "usually fails, one
  lucky pass." A handful of repeat runs would help establish a real failure rate.
- **Whether `streamWithRetries`' retry logic (`maxRetries: 3`, `IOSAgent.swift:227-232`) is
  involved.** Each of the ~47 "invisible" iterations could itself be silently retrying network
  calls up to 3 times without necessarily producing an info-level log each time — worth checking
  `streamWithRetries`' own logging level while investigating.

## Two separate, real issues bundled in this symptom

1. **The model-behavior question** (does gpt-5-nano genuinely get stuck failing to call tools or
   produce JSON, and if so, is this specific to nano or would other small/fast models show the
   same pattern?) — needs the debug rerun above to even start answering.
2. **An app-side reliability gap, independent of which model is at fault**: this failure mode
   (a) is completely invisible without manually bumping to debug logging, and (b) doesn't produce
   a saved report — combined, a `gpt-5-nano`-style silent 25-minute hang in CI or an unattended
   batch run would look like "the process hung," with no artifact to diagnose afterward beyond
   whatever raw stdout happened to be captured externally. Worth considering independent of
   whatever the eventual model-behavior verdict is:
   - Should `TestRunner`/`IOSAgent` save a report (or at least append partial `runHistory`) even
     when hitting `Error.unexpectedResponse` from exhausted iterations, not just on other failure
     paths?
   - Should the loop fail faster when N consecutive iterations produce neither a tool call nor
     valid JSON (e.g. bail after 5-10 consecutive non-actionable responses instead of burning the
     full 50-iteration/many-minute budget)? Would turn a 25-minute silent hang into a fast, clear
     "model isn't following the tool-call protocol" failure.

## Suggested first concrete steps for the next investigation session

1. Rerun the Reminders fixture with `gpt-5-nano` specifically at `--log-level debug`, several
   times in a row if budget allows, to (a) see the actual assistant text produced during any
   silent-looking gap, and (b) get a real sample size on how often this reproduces:
   ```bash
   xcodeproject/DerivedData_local/Build/Products/Debug/Qalti.app/Contents/MacOS/Qalti cli \
     tests/reminders_create_and_verify.test --model gpt-5-nano --device-name "<booted sim>" \
     --log-level debug 2>&1 | tee /tmp/gpt5nano_debug_run1.log
   ```
2. Grep the resulting debug log for the assistant's actual streamed content
   (`runHistory.append(.assistant(...))` calls suggest the raw text is retained in
   `runHistory` — check whether there's an existing debug log line that dumps
   `streamed.assistantContent` directly, or add a temporary one if not, right around
   `IOSAgent.swift:236-250`).
3. Once the real behavior is visible, decide whether this is a genuine model-capability limit
   (in which case: is `gpt-5-nano` worth keeping in `TestRunner.AvailableModel` at all, or should
   it be flagged/deprioritized as unreliable for this kind of test?) vs. an app-side prompt/parsing
   issue worth fixing generally.
4. Independent of the root cause, consider the two app-side reliability improvements listed above
   (save a report on `Error.unexpectedResponse` too; fail fast after N consecutive non-actionable
   iterations) as their own small, valuable fixes regardless of what's actually wrong with nano.

## Repro environment details (for reference)

- Fixture used both times: `tests/reminders_create_and_verify.test` (the self-proving,
  `{{RUN_ID}}`-templated version — see `docs/investigations/open-app-timeout.md` for why the earlier Notes
  fixture was replaced).
- Passing run: `scripts/output/notes_model_matrix_20260729_144842/gpt-5-nano.log`
- Failing run: `scripts/output/notes_model_matrix_20260729_203638/gpt-5-nano.log`
- Relevant source: `xcodeproject/Qalti/Services/Agent/IOSAgent.swift:220-297` (main loop),
  `:683-703` (`shouldRejectToolCallsWithoutComment`, ruled out as the cause here), `:801-807`
  (`logPlannedAction`, only place the `.info`-level "Agent Iteration #X/Y" line is printed).
- This is unrelated to `open_app` (already fixed), the two Gemini decoding crashes (documented,
  separate root cause), or the two stale model IDs (`grok-4`, `gemini-3-pro-preview`) — do not
  conflate when re-running matrices. See `docs/openrouter_models.md` and `docs/follow-ups.md`.
