# Investigation: `gemini-2.5-pro` / `gemini-3-flash-preview` crash Qalti's response decoding

## Status: FIXED 2026-07-31

Implemented "Fix option 1" below (middleware-based sanitization via `interceptStreamingData`) in
`ErrorDecodingMiddleware` (`xcodeproject/Qalti/Services/Agent/IOSAgent.swift:68-`). Verified
end-to-end against both live models on iPhone 16e (iOS 26.0) using the Reminders fixture:

- `gemini-2.5-pro`: no decode error; `testResult.test_result: "pass with comments"`,
  `test_objective_achieved: true`.
- `gemini-3-flash-preview`: no decode error; `testResult.test_result: "pass"`,
  `steps_followed_exactly: true`.

The implementation buffers raw network chunks into complete SSE `data: {...}` lines (a single
`didReceive data:` call isn't guaranteed to align with line boundaries), then for each line
strips unrecognized `service_tier` values and back-fills whichever field a `reasoning_details`
entry's `type` requires (`text`/`data`/`summary`) with `""` if missing — before the vendored
package's decoder ever sees the bytes. Lines needing no patch pass through byte-identical. No
dependency fork/patch was needed, as hoped in "Fix option 1" below.

The rest of this document is kept as-is for historical/reference context (the original
investigation, alternatives considered, and why bumping the dependency wouldn't have helped).

## Context / how this was found

Branch: `feature/openrouter_model_tooling`. Found during the same 10-model matrix effort that
also uncovered and fixed the `open_app` timeout bug (see `OPEN_APP_TIMEOUT_INVESTIGATION.md`,
already resolved — not related to this investigation).

Two of the hardcoded model IDs in `TestRunner.AvailableModel`
(`xcodeproject/Qalti/Services/Agent/TestRunner.swift:39-65`) are **live and reachable** on
OpenRouter's catalogue (unlike `grok-4`/`gemini-3-pro-preview`, which are simply stale/404 —
see `stale_openrouter_model_ids` memory, a separate and already-understood issue), but every run
against them crashes with a `DecodingError` inside Qalti's vendored OpenAI Swift client, before
the agent ever gets a usable response:

- `google/gemini-2.5-pro` (`TestRunner.AvailableModel.gemini25pro`)
- `google/gemini-3-flash-preview` (`TestRunner.AvailableModel.gemini3flashPreview`)

Both surface identically at the CLI level as a **hard, non-zero-exit failure**
(`IOSAgent.Error` → "Received unexpected response from AI service" → CLI prints
`Test failed: Received unexpected response from AI service`). This is a real crash, not the
agent "deciding" the test failed — so it is *not* subject to the CLI's forced-success override
(`TestRunner.swift:414-418`; see `cli_forced_success` memory) and both CLI exit code and banner
are accurate here.

## Exact symptom (log excerpts)

`gemini-2.5-pro`:
```
[IOSAgent] AWS S3 credentials missing; using base64 screenshots
[ErrorCapturerService] Captured error: The data couldn't be read because it is missing.
[IOSAgent] LLM stream completion error [s1]: DecodingError.keyNotFound: Key 'text' not found in
    keyed decoding container. Path: choices[0].delta.reasoning_details[0]. Debug description:
    No value associated with key CodingKeys(stringValue: "text", intValue: nil) ("text").
[ErrorCapturerService] Captured error: The data couldn't be read because it is missing.
[IOSAgent] API call failed: DecodingError.keyNotFound: ... (same)
[IOSAgent] Response format mismatch from OpenRouter: DecodingError.keyNotFound: ... (same)
[ErrorCapturerService] Captured error: Received unexpected response from AI service
[RunnerManager] Stopping runner xcodebuild process
[CLI] Test failed: Received unexpected response from AI service
```

`gemini-3-flash-preview`:
```
[IOSAgent] AWS S3 credentials missing; using base64 screenshots
[ErrorCapturerService] Captured error: The data couldn't be read because it isn't in the correct format.
[IOSAgent] LLM stream completion error [s1]: DecodingError.dataCorrupted: Data was corrupted.
    Path: service_tier. Debug description: Cannot initialize ServiceTier from invalid String
    value provisioned
[ErrorCapturerService] Captured error: The data couldn't be read because it isn't in the correct format.
[IOSAgent] API call failed: DecodingError.dataCorrupted: ... (same)
[IOSAgent] Response format mismatch from OpenRouter: DecodingError.dataCorrupted: ... (same)
[ErrorCapturerService] Captured error: Received unexpected response from AI service
[RunnerManager] Stopping runner xcodebuild process
[CLI] Test failed: Received unexpected response from AI service
```

Both crash on the **very first streamed chunk** (`[s1]`), before any agent action can be taken —
the model itself never gets a chance to do anything wrong; this is purely a client-side parsing
failure of an otherwise valid OpenRouter response.

## Root cause: both bugs live in a vendored third-party dependency, not Qalti's own code

Qalti uses MacPaw's `OpenAI` Swift package via a **fork**, pinned in SPM to a specific commit on
the fork's `main` branch (not a semver release):

```
# xcodeproject/Qalti.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
"identity" : "openai",
"location" : "https://github.com/elrid/OpenAI.git",
"state" : { "branch" : "main", "revision" : "781e69a4664d3f874b0d100db9b7663bc04f1614" }
```
(vendored/checked-out copy readable locally at
`.cache/xcode/SPMClones/checkouts/OpenAI/Sources/OpenAI/`)

### Bug 1 — `gemini-2.5-pro`: `ReasoningDetail.ReasoningText.text` is non-optional, but a streamed delta chunk can omit it

`Sources/OpenAI/Public/Models/ChatResult.swift:159-226` defines `ReasoningDetail`, an enum with a
custom `init(from:)` that reads a `type` discriminator field and dispatches to one of three
payload structs:
```swift
public enum ReasoningDetail: Codable, Equatable, Sendable {
    case text(ReasoningText)
    case encrypted(ReasoningEncrypted)
    case summary(ReasoningSummary)

    public struct ReasoningText: Codable, Equatable, Sendable {
        public let type: String
        public let text: String        // <-- required, non-optional
        public let format: String?
        public let index: Int?
    }
    // ReasoningEncrypted / ReasoningSummary similarly shaped

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "reasoning.text":
            self = .text(try ReasoningText(from: decoder))   // <-- throws if `text` key missing
        ...
        default:
            throw DecodingError.dataCorruptedError(...)       // unknown type also throws
        }
    }
}
```
This type is also reused verbatim for the *streaming* delta shape
(`ChatStreamResult.swift:111-129`, `public typealias ReasoningDetail = ChatResult.Choice.Message.ReasoningDetail`).
Non-streaming (final, complete) responses presumably always carry `text` — but for **incremental
SSE chunks**, providers commonly split a field across multiple deltas (e.g. chunk 1 carries
`type`+`format`+`index` with an empty/absent `text` to be filled by later chunks, mirroring how
`delta.content` itself streams token-by-token). Gemini 2.5 Pro's `reasoning_details[0]` in the
very first delta apparently omits `text` entirely, and the strict `Codable` synthesis for
`ReasoningText` throws instead of tolerating a missing/absent value on a per-delta basis.

**This is not a stale-package problem** — checked via GitHub (`elrid/OpenAI`) commit history on
`ChatResult.swift`: the pinned revision `781e69a4...` IS itself the fork's most recent
reasoning-related commit ("Add support for gpt-5 reasoning details", ~Dec 17 2025). There is no
newer upstream commit to pull in that would fix this — the leniency gap has to be fixed locally
(fork patch, or working around it in Qalti's own code — see "Fix options" below).

### Bug 2 — `gemini-3-flash-preview`: `ServiceTier` is a closed enum with no fallback case

`Sources/OpenAI/Public/Models/Types/ServiceTier.swift` (whole file):
```swift
public enum ServiceTier: String, Codable, Hashable, Sendable, CaseIterable {
    case auto = "auto"
    case defaultTier = "default"
    case flexTier = "flex"
}
```
This is a plain `String`-backed `RawRepresentable` enum. Swift's synthesized `Codable`
conformance for such an enum throws `DecodingError.dataCorrupted` when the raw string doesn't
match any known case — exactly what happened: OpenRouter returned `"service_tier": "provisioned"`
for this model, a value not represented here.

Checked via GitHub: `ServiceTier.swift` has had **exactly one commit ever** (May 22, 2025, "Add
service_tier and test encoding") — it has never been revisited to add new tiers or tolerate
unknown ones. Same conclusion as Bug 1: **no newer upstream revision exists to bump to** for
this specific issue.

## Fix options considered

1. **Preferred — sanitize the raw bytes before the package decodes them, via the existing
   middleware hook, entirely within Qalti's own code (no fork/patch needed).**
   `OpenAIMiddleware` (the protocol Qalti's own `IOSAgent.ErrorDecodingMiddleware` and
   `OpenRouterPointOutService`'s equivalent already conform to) exposes:
   ```swift
   // Sources/OpenAI/Public/Protocols/OpenAIMiddleware.swift
   public protocol OpenAIMiddleware: Sendable {
       func intercept(request: URLRequest) -> URLRequest
       func interceptStreamingData(request: URLRequest?, _ data: Data) -> Data   // <-- unused today
       func intercept(response: URLResponse?, request: URLRequest, data: Data?) -> (response: URLResponse?, data: Data?)
   }
   ```
   Qalti's `ErrorDecodingMiddleware` (`IOSAgent.swift:68-107`) currently only implements
   `intercept(response:request:data:)` (used for 401/402/504 detection) — it does **not**
   implement `interceptStreamingData`, which is called on each raw SSE chunk's bytes *before* the
   package attempts to decode it into `ChatStreamResult`. Implementing it there would let us:
   - Rewrite/strip `reasoning_details` entries missing a `text` key (or inject `"text": ""`)
     before decode.
   - Rewrite unrecognized `service_tier` string values (e.g. `"provisioned"`) to a known case
     (e.g. `"default"`) before decode.
   This keeps the fix entirely inside Qalti's codebase, doesn't require forking/patching the
   vendored dependency, and follows a pattern the codebase already uses (middleware-based response
   massaging). The same middleware class is shared by `IOSAgent.swift` and would need the
   equivalent added to `OpenRouterPointOutService.swift`'s own private `ErrorDecodingMiddleware`
   too if used there.

2. **Fork the vendored package ourselves and patch the two structs directly** (make
   `ReasoningText.text` optional; make `ServiceTier` a manually-implemented `Codable` with an
   `.other(String)` fallback case). More invasive — changes a third-party dependency's pinned
   revision to a custom fork/branch, adds maintenance burden, but is the "more correct" long-term
   fix if this fork is meant to track upstream compatibility fixes generally rather than
   accumulate app-side patches.

3. **File the issue upstream against `elrid/OpenAI`** and wait for a fix, bump the pin once
   available. Slowest option; blocks on someone else's timeline; not mutually exclusive with
   option 1 as a stopgap.

Recommendation: start with option 1 (middleware sanitization) as the immediate fix since it's
low-risk and self-contained; consider option 3 as a parallel, non-blocking upstream contribution.

## Suggested first concrete steps for the next investigation/implementation session

1. Reproduce the two crashes in isolation for fast iteration:
   ```bash
   xcodeproject/DerivedData_local/Build/Products/Debug/Qalti.app/Contents/MacOS/Qalti cli \
     tests/reminders_create_and_verify.test --model gemini-2.5-pro --device-name "<booted sim>" \
     --log-level debug
   ```
   (repeat with `--model gemini-3-flash-preview`). Note: use the fixed Reminders fixture, not the
   old Notes one — see `OPEN_APP_TIMEOUT_INVESTIGATION.md` for why Notes is unusable on iOS 26.x
   simulators, unrelated to this bug.
2. Capture one real raw SSE chunk for each crash (e.g. temporarily log `interceptStreamingData`'s
   raw `data` before implementing any sanitization, or reproduce via a direct `curl` against
   `https://openrouter.ai/api/v1/chat/completions` with `stream: true` and the same model/messages)
   to see the exact JSON shape being sent — confirm whether `reasoning_details[0]` really omits
   `text` outright vs. sends it as `null` or an empty string (changes exactly how lenient the
   patch needs to be), and confirm what other `service_tier` values might appear beyond
   `"provisioned"` (check OpenRouter's docs/changelog if available).
3. Implement `interceptStreamingData` in `IOSAgent.ErrorDecodingMiddleware`
   (`IOSAgent.swift:68-107`) to sanitize the two known-bad shapes. Keep the transformation
   narrowly scoped (regex/JSON-surgical, not a full re-serialize) to avoid subtly breaking valid
   responses from other providers.
4. Add the equivalent to `OpenRouterPointOutService.swift`'s private `ErrorDecodingMiddleware`
   (lines 26-52) if point-out/vision calls could plausibly hit either model too (check
   `Constants.model` there — currently hardcoded to `"anthropic/claude-sonnet-4"`, so may not be
   an immediate concern, but worth a quick check if the model becomes configurable later).
5. Rebuild, then re-run the model matrix (`scripts/run_notes_model_matrix.sh`, now pointed at the
   Reminders fixture) filtered to just these two models to confirm both now complete without a
   `DecodingError`, and verify the ground-truth-checked pass/fail via the report JSON's top-level
   `testResult` field (not the CLI banner — see `cli_forced_success` memory).
6. If option 1 proves fragile (new unknown fields keep appearing over time), reconsider option 2
   (forking the dependency for proper optional/lenient `Codable` semantics) as a more durable fix.

## Repro environment details (for reference)

- Vendored dependency: `https://github.com/elrid/OpenAI.git`, branch `main`, pinned revision
  `781e69a4664d3f874b0d100db9b7663bc04f1614` (this IS the tip of the fork's `main` as of this
  investigation for both affected files — re-verify if picked up later, in case upstream has
  moved since).
- Affected source (readable locally, not part of Qalti's own target):
  `.cache/xcode/SPMClones/checkouts/OpenAI/Sources/OpenAI/Public/Models/ChatResult.swift:159-226`
  and `.../Public/Models/Types/ServiceTier.swift`.
- Qalti's own middleware entry point to fix from:
  `xcodeproject/Qalti/Services/Agent/IOSAgent.swift:68-107` (`ErrorDecodingMiddleware`), and
  `xcodeproject/Qalti/Services/UIHelpers/OpenRouterPointOutService.swift:26-52` (separate,
  parallel middleware class for the point-out/vision flow).
- These two models are unrelated to the (already-fixed) `open_app` timeout bug and the
  (already-known) stale `grok-4`/`gemini-3-pro-preview` model IDs — do not conflate the four
  issues when re-running matrices; see `MEMORY.md` project memory index for the full picture.
