# Investigation: `open_app` reliably times out in Qalti CLI runs

## Context / how this was found

Branch: `feature/openrouter_model_tooling` (also relevant on `main` — nothing here is specific
to that branch's own changes, except that two real bugs were fixed on it first; see below).

While smoke-testing OpenRouter model IDs hardcoded in `TestRunner.AvailableModel`
(`xcodeproject/Qalti/Services/Agent/TestRunner.swift:39-65`), a matrix of CLI runs was executed:
`tests/notes_create_and_verify.test` (a plain-text scenario: `Open Notes` / create a note / verify
it saved) run once per model via `xcodeproject/DerivedData_local/Build/Products/Debug/Qalti.app/Contents/MacOS/Qalti cli ...`
against a booted "iPhone 17" (iOS 26.0) Simulator, macOS 26.4.1, Xcode 26.2.

Result: **every model that successfully authenticated and got a response from OpenRouter still
failed the test**, and all of them failed at the identical first step — trying to open the Notes
app. A similar symptom appeared earlier in the same session on a different app/test
(`tests/syncups_change_theme.test` with a freshly-installed SyncUps.app): the agent tried to
`open_app(app_name="QaltiUITests-Ru...")` — the **test-runner harness itself**, not "SyncUps" —
and that also timed out twice before failing.

Because the failure is consistent across ~6 different LLM models and 2 different target apps
(one built-in, one freshly side-loaded), this strongly points to a bug in Qalti's own
app-launch/simulator-interaction tooling rather than anything model-specific. That tooling bug is
the subject of this investigation. (Two *other*, unrelated real bugs were found and fixed during
the same session — a CLI auth-key wiring bug, and pre-flight credential guards checking the wrong
property — those are already fixed and are not part of this investigation; see "Already-fixed
context" below if you want the full picture, but they should not need re-checking.)

## Exact symptom (log excerpts)

Notes scenario, `gpt-5` (representative of all 6 working-auth models — same pattern every time):
```
[IOSAgent] Agent Iteration #01/50:
    Qalti Action: open_app(app_name="com.apple.mobilenotes")
[ErrorCapturerService] Captured error: The request timed out.
[IOSAgent] Agent Iteration #02/50:
    Qalti Action: open_app(app_name="Notes")
[ErrorCapturerService] Captured error: The request timed out.
[IOSAgent] Agent Iteration #04/50:
    Qalti Action: open_url(url="mobilenotes://", post_action_delay=5.0)
[ErrorCapturerService] Captured error: The request timed out.
[TestRunner] CLI MODE: Agent failed, but forcing SUCCESS to match legacy behavior.
```
(Note: despite that last line and the CLI printing "Test completed successfully", the real
verdict — recoverable from the saved report JSON's top-level `testResult` field — was
`"test_result": "failed"`, `"test_objective_achieved": false`, comments describing the app
launch as blocking all further steps. The CLI's own success/failure banner is not trustworthy;
see "Known unrelated gotchas" below.)

SyncUps scenario, `gpt-4.1`, different app but same shape of failure:
```
[IOSAgent] Agent Iteration #01/50:
    Qalti Action: open_app(app_name="QaltiUITests-Ru...")
... (list_apps / installedApplications calls succeed via idb, app was installed successfully
     just beforehand — "App installed successfully: co.kslavnov.SyncUps" logged) ...
[ErrorCapturerService] Captured error: The request timed out.
[IOSAgent] Agent Iteration #02/50:
    Qalti Action: open_app(app_name="QaltiUITests-Ru...")
[ErrorCapturerService] Captured error: The request timed out.
```
Here the agent picked the **wrong app name entirely** — the test-runner harness
(`QaltiUITests-Runner`) instead of "SyncUps" — suggesting the app list/labels the agent sees may
be confusing or ambiguous, in addition to (or instead of) a pure timeout mechanism problem.

## Full technical code map (verified via code reading, with line numbers)

### Tool call path (LLM → execution)
- Tool schema registered: `Qalti/Services/Agent/Prompts.swift:848` (params: `app_name`,
  `launch_arguments`, `launch_environment`; description text in `tool_open_app.txt`).
- Decoded into a typed command: `Qalti/Services/Agent/TargetCommand.swift:382` (`"open_app"`
  case), also listed at `TargetCommand.swift:232`.
- Tool-call execution loop: `Qalti/Services/Agent/IOSAgent.swift:706-770` (`runToolCalls`).
  Key detail — **the wait for a tool call's completion has no timeout**:
  ```swift
  // IOSAgent.swift:733-740
  var toolResponseOpt: ToolResponse? = nil
  let group = DispatchGroup()
  group.enter()
  commandExecutorTools.executeCommand(command, errorCapturer: errorCapturer) { response in
      toolResponseOpt = response
      group.leave()
  }
  group.wait()   // no deadline — blocks indefinitely at this layer
  ```
  So whatever timeout is actually firing ("The request timed out.") must come from a lower layer,
  not from this dispatch loop itself.
- Dispatch to concrete implementation: `Qalti/Services/Agent/CommandExecutorToolsForAgent.swift:802-828`
  (`executeCommand`), line 807 routes `.openApp(...)` to:
  ```swift
  // CommandExecutorToolsForAgent.swift:626-643
  func open_app(name: String, launchArguments: [String]?, launchEnvironment: [String: String]?,
                completion: @escaping (ToolResponse) -> Void) {
      executeActionWithScreenshot(
          action: { [weak self] actionCompletion in
              self?.runtime.openApp(name: name, launchArguments: launchArguments,
                                     launchEnvironment: launchEnvironment, completion: actionCompletion)
          },
          postActionDelay: 5.0
      ) { runtimeResponse in ... }
  }
  ```
- A second, legacy code path for raw-script `open_app(...)` calls exists at
  `Qalti/Services/Runtime/IOSRuntime.swift:582-669` (used by `run_script` /
  `TargetViewModel.swift:357`), which parses arguments itself then calls the same
  `openApp(name:...)` at line 669. (The agent used the tool-call path in the observed logs, not
  this one, but it's worth knowing both exist and both bottom out at the same `openApp`.)

### App-name → bundle-ID resolution (likely root-cause area)
All in `Qalti/Services/Runtime/AppBundleResolver.swift` (82 lines total):
- `resolveBundle(for:)` (lines 72-79): calls `listApps()` **fresh every single call** (no
  caching), normalizes the input name via `normalizeAppKey` (lines 19-25: lowercases, strips
  spaces, strips a trailing "app"), and does an **exact dictionary lookup only — no fuzzy
  matching**. If the normalized name isn't found, it returns the **raw input string unchanged**
  as if it were a bundle ID (line 78) — which would then be an invalid bundle ID and fail
  downstream, likely surfacing as exactly this kind of opaque timeout/failure rather than a clear
  "app not found" error.
- `listApps()` (lines 28-69): calls `idbManager.listApps(udid: deviceId)`
  (→ `Qalti/Services/Runtime/idb.swift:677-712`) for the live installed-app list from
  `idb_companion` via gRPC, then **merges in a hardcoded dictionary of ~16 system apps**
  (lines 41-58). **"Notes" is not in that hardcoded list** — resolving "Notes" therefore depends
  entirely on idb's live `list_apps` response containing it correctly (right name key, right
  casing, etc).
- `idb.swift:677-712` (`listApps(udid:)`):
  ```swift
  public func listApps(udid: String) throws -> [(name: String, bundleID: String)] {
      guard let connection = activeConnections[udid] else { throw IdbError.notConnected(udid: udid) }
      let request = Idb_ListAppsRequest.with { req in req.suppressProcessState = false }
      let semaphore = DispatchSemaphore(value: 0)
      var taskError: Error?
      var apps: [(name: String, bundleID: String)] = []
      Task {
          do {
              let response = try await connection.client.list_apps(request)
              apps = response.apps.map { (name: $0.name, bundleID: $0.bundleID) }
          } catch { errorCapturer.capture(error: error); taskError = error }
          semaphore.signal()
      }
      semaphore.wait()   // also unbounded — no gRPC CallOptions(timeLimit:) set
      if let error = taskError { throw error }
      return apps
  }
  ```
  No timeout/deadline is passed to the gRPC `list_apps` call. If `idb_companion` is slow or hung
  — plausible right after a fresh app install (`SyncUps` case) or simply under load — this
  semaphore wait blocks with no bound, which could itself present as "the request timed out" if
  some *other*, outer layer (see below) has its own timeout that eventually fires.
- `IOSRuntime.swift:271-293` (`openApp`): calls `appBundleResolver.resolveBundle(for: name)`,
  builds an `.openApp` `RunnerCommand` (`IOSRuntimeRequestBuilder.swift:18,67,128-138`), and POSTs
  it to the on-device HTTP runner at `/open-app` (`IOSRuntime.swift:290`,
  builder at `IOSRuntimeRequestBuilder.swift:37-57`).

### Where a timeout could actually be firing
- `IOSRuntimeRequestBuilder.swift:37-57`: the `URLRequest` built for `/open-app` **never sets
  `timeoutInterval`**. The session is `URLSessionConfiguration.ephemeral`
  (`IOSRuntime.swift:36-47`) with no `timeoutIntervalForRequest` override — so it falls back to
  Foundation's default **60-second** request timeout. This is the most likely source of "The
  request timed out." for a genuinely-hung on-device call.
- `IOSAgent.swift:155` — the `240.0`-second `timeout` constant is for the **OpenRouter chat
  completion HTTP client** (`prepareQuery`, line ~585, `timeoutInterval: timeout`), reused for the
  initial-screenshot wait (line ~524) and the LLM stream wait (line ~669). This is unrelated to
  `open_app`'s own timeout and should not be confused with it.
- The on-device runner server itself (the injected `QaltiRunner`/UI-test-runner binary that
  receives the `/open-app` HTTP POST) is **not part of this Swift app's source tree** in the
  searched locations — its own internal timeout/handling of an app-launch request (e.g. does it
  wait synchronously for `XCUIApplication().activate()`/`launch()` to return, itself possibly
  hanging on iOS 26 specifically?) has not yet been investigated and may be the actual site of
  the hang. Look for the runner's source (likely `QaltiRunner`/`QaltiRunnerLib` targets referenced
  in DEVELOPER.md's "Simulator Runner Artifacts" step) for how `/open-app` is handled server-side.

### Caching / staleness
- No caching exists in `AppBundleResolver` itself — it re-fetches from idb on every call. So a
  "stale list from before SyncUps was installed" is unlikely to be the direct explanation *for
  that specific symptom*, assuming idb's `list_apps` reflects installs immediately. This points
  investigation toward either (a) `idb_companion`'s own internal delay/caching after
  `simctl install` (outside this Swift codebase — the bundled binary is at
  `Qalti/Resources/simulatorbinaries/bin/idb_companion`, built per its own startup log "Jul 14
  2025"), or (b) a race where `open_app` is called before the simulator's `installd`/springboard
  has fully registered the new app, or (c) the persistent gRPC connection in
  `idb.swift`'s `activeConnections` (keyed by UDID) being stale/broken for the run.

### Known environment noise observed (may or may not be related — listed for completeness)
- `objc[...]: Class FBProcess is implemented in both /System/Library/PrivateFrameworks/FrontBoard.framework
  and .../simulatorbinaries/Frameworks/FBControlCore.framework` — a duplicate-class warning at
  idb_companion startup every run. Apple's runtime picks one; "may cause spurious casting failures
  and mysterious crashes" per the warning text itself. Worth ruling in/out.
- `nw_listener_socket_inbox_create_socket bind(...) Address already in use` for the
  screenshot/control server ports (9847/9848) was observed on more than one run — suggests a
  previous `QaltiUITests-Runner` process/port wasn't fully torn down between runs. Could indicate
  general process/resource leakage in the runner lifecycle that might also affect app-launch
  reliability under repeated/sequential runs (as in a model matrix), separate from a single fresh
  run.
- Multiple simulators can be left in "Booted" state simultaneously in this environment (observed:
  3 booted UDIDs at once) — not a cause of the `open_app` bug itself (each run correctly targeted
  a specific UDID via `--udid`/`--device-name`), but worth knowing about if reproducing manually.

## Known unrelated gotchas in this codebase (do not re-investigate, just be aware)

- **CLI "forces success"**: `TestRunner.swift:414-418` overwrites an agent-judged failure to
  "success" in CLI mode. The CLI's own exit code / "Test completed successfully" banner is NOT a
  reliable verdict. The real result is in the saved report JSON's top-level `testResult` object
  (`test_result`, `test_objective_achieved`, `comments`). Use that field when evaluating any test
  run's actual outcome, not the CLI banner.
- **`--report-path` is broken**: parsed into `config.testRunPath` but never wired into the actual
  save path used by `TestRunner.saveTestRun`/`context.testRunURL(for:preferredName:)`. Reports
  always land at the default `~/Documents/Qalti/Runs/test_run_<timestamp>.json` regardless of
  `--report-path`. Find the real path by grepping a run's own stdout for `"Report saved to:"`.
- A CLI-auth-key wiring bug (`credentialsService.openRouterKey` vs `.bearer`) was found and fixed
  in `IOSAgent.swift`, `OpenRouterPointOutService.swift`, `TestRunner.swift`, `TestSuiteRunner.swift`
  earlier in this session — already fixed, not related to `open_app`.

## Ranked hypotheses to test

1. **Bundle-ID resolution silently fails and passes garbage downstream.** `resolveBundle`
   returns the raw, unresolved name as a fake "bundle ID" when lookup fails
   (`AppBundleResolver.swift:78`) instead of surfacing an error. Test: add temporary logging (or
   set a breakpoint) in `resolveBundle`/`listApps` to print the exact list of `(name, bundleID)`
   pairs `idb_companion` returns for "Notes" at the moment `open_app("Notes")` runs, and confirm
   whether "Notes" is actually present with the expected name/casing. Do the same for "SyncUps" to
   see if `QaltiUITests-Runner` genuinely appears as a candidate app entry that the LLM could
   plausibly (mis)match against "SyncUps".
2. **The on-device runner's `/open-app` HTTP handler itself hangs** (in the `QaltiRunner`/UI-test
   target, not yet located in this investigation) — e.g., synchronously blocking on
   `XCUIApplication.launch()`/`.activate()` for a springboard-driven app on iOS 26 specifically.
   Test: reproduce manually via `xcrun simctl launch <udid> com.apple.mobilenotes` directly (does
   plain `simctl launch` succeed instantly, ruling out a simulator-level Notes-launch problem?),
   then separately try to trigger the same `/open-app` HTTP endpoint the runner exposes (find its
   port/route by reading the `QaltiRunner`/`QaltiRunnerLib` source, likely referenced from
   `xcodeproject/scripts/archive_simulator_runner.sh` and the Xcode project's UI-test target) to
   see if the HTTP call itself hangs for exactly ~60s (matching the default `URLRequest` timeout)
   or longer/shorter.
3. **`idb_companion`'s gRPC `list_apps` call hangs**, and the eventual "The request timed out."
   message actually originates from the *unrelated* 60s `/open-app` HTTP request timeout firing
   later in the same tool call, masking the true hang location. Test: add timing/logging around
   `idb.swift:705`'s `semaphore.wait()` specifically, independent of the `/open-app` HTTP call.
4. **Stale/broken persistent gRPC connection** in `idb.swift`'s `activeConnections`. Test: check
   whether restarting the whole IDB companion process (fresh `idb_companion` per CLI run — which
   the code appears to already do, based on logs showing a fresh "IDB Companion Built..." /
   "Swift server started on tcp port ..." line per run) rules this out, or whether some Simulator
   Runner Artifact staleness (see DEVELOPER.md "When to Rebuild Simulator Runner Artifacts")
   could be a factor if `QaltiRunnerLib` hasn't been rebuilt recently relative to source changes.
5. **The duplicate `FBProcess` class warning is not cosmetic** and actually causes intermittent
   misbehavior in FrontBoard-mediated app launches (Apple's own warning text: "may cause spurious
   casting failures and mysterious crashes"). Test: see if this warning correlates with failures
   vs. successes across more runs, or try renaming/removing one of the duplicate
   `FBControlCore.framework` copies to see if the warning (and any correlated failures) disappear.

## Suggested first concrete steps for the next investigation session

1. Reproduce a single minimal case: `Qalti cli` with a 1-line test file containing only
   `Open Notes`, `--model gpt-4.1`, `--device-name "iPhone 17"` (or whichever simulator is
   booted), with `--log-level debug` for maximum verbosity. Confirm the timeout reproduces in
   isolation (it should, based on the matrix data).
2. Add temporary debug logging in `AppBundleResolver.resolveBundle`/`listApps`
   (`Qalti/Services/Runtime/AppBundleResolver.swift:28-79`) to print the full list of apps
   idb reports and the resolved bundle ID actually used for the `/open-app` request — this is the
   cheapest, most direct way to falsify or confirm hypothesis #1 before touching anything else.
3. If bundle resolution looks correct, add logging/timing around the `/open-app` HTTP request
   itself (`IOSRuntime.swift:271-293`, `IOSRuntimeRequestBuilder.swift:37-57`) to see exactly how
   long it takes before failing and what the on-device runner server actually responds (or
   whether it responds at all).
4. Locate and read the on-device runner's HTTP server implementation (the `QaltiRunner`/
   `QaltiRunnerLib` / `QaltiUITests` targets — see DEVELOPER.md's "Step 1: Generate Simulator
   Runner Artifacts" and "When to Rebuild Simulator Runner Artifacts" sections for where these
   live) to see how it implements the `/open-app` route and whether it can itself hang.
5. Try a plain `xcrun simctl launch <udid> com.apple.mobilenotes` outside of Qalti entirely, to
   establish a baseline for whether iOS 26.0 Simulator + this Xcode version has any known
   general app-launch flakiness unrelated to Qalti's own code.

## UPDATE 2026-07-27: simulator contention (superseded — see the 2026-07-28 update below)

An intermediate conclusion, kept only so the reasoning trail stays complete. Inspecting live system
state while the symptom was fresh showed a badly loaded machine: several simulators booted at once,
a runaway `backboardd` pegging a core for hours, an intermittently unresponsive
`CoreSimulatorService`/`simdiskimaged`, and — the apparent smoking gun — the target UDID being
driven concurrently by an unrelated project's UI-test runner. "Simulator resource contention"
looked like the root cause.

It was not. The symptom reproduces on a dedicated, uncontended machine (next section), so the
contention was real but incidental. One durable lesson survives it: Qalti had no explicit deadline
on either the gRPC `list_apps` call or the `/open-app` HTTP request, so under load it degraded into
an opaque hang rather than failing fast with a usable error — a robustness gap regardless of root
cause, and the reason this took three sessions to pin down.

## UPDATE 2026-07-28: Actual root cause confirmed — **Notes is not installable/launchable on iOS 26.x simulators**. Contention theory superseded.

Re-checked on a machine dedicated to this task (no other projects driving simulators — verified:
exactly **one** booted simulator, `AFB3DA76-2A11-46CD-ADAB-EFE24128ED27` "iPhone 16e" iOS 26.2, no
foreign app/runner processes). The 2026-07-27 contention conclusion therefore cannot explain the
symptom, and it reproduces anyway. Direct evidence gathered:

### 1. The Notes scenario was impossible from the start (primary root cause — CONFIRMED)
`xcrun simctl launch <udid> com.apple.mobilenotes`, run **outside Qalti entirely** (doc's
never-executed "suggested step 5"), fails **immediately** (~0.9 s, not a timeout):
```
An error was encountered processing the command (domain=FBSOpenApplicationServiceErrorDomain, code=4):
Simulator device failed to launch com.apple.mobilenotes.
```
`xcrun simctl listapps <udid>` returns 32-35 apps and **contains no `com.apple.mobilenotes`** at all.
This is **not** device corruption or a stale boot: a **freshly created + booted** iOS 26.2 device
(created and deleted during this session as a control) shows the identical result — 32 apps, no
Notes, launch fails instantly. Meanwhile `com.apple.Preferences`, `com.apple.mobilesafari` and
`com.apple.MobileAddressBook` all launch **successfully and instantly** on the same device, so
SpringBoard/FrontBoard and the simulator generally are healthy.

Note the subtlety: `MobileNotes.app` **does** exist inside every runtime image on disk (checked iOS
16.4 → 26.4; iOS 26.2's RuntimeRoot has 236 apps including MobileNotes.app), but it is **not
registered with the device's installd/LaunchServices** and cannot be launched. So "the runtime has
Notes" is not the same as "the device can open Notes" — don't use runtime-image contents as evidence.

**Consequence:** every one of the 6 working-auth models failed identically at step 1 because the
task was *unachievable*, not because of the model, not (primarily) because of simulator contention.
`tests/notes_create_and_verify.test` is an invalid fixture on this platform and its results say
nothing about model quality or about Qalti's agent loop.

### 2. Qalti turns "app not installed" into an opaque 60 s timeout (real bug — hypothesis #1 CONFIRMED)
The code path is now confirmed against the live app list. `AppBundleResolver.listApps()`
(`AppBundleResolver.swift:41-58`) hardcodes 16 system apps and **Notes is not among them**; the idb
list doesn't contain Notes either. So `resolveBundle(for: "Notes")` falls through to line 78 and
returns the string `"Notes"` **verbatim, as if it were a bundle ID**. That bogus ID is then POSTed to
the on-device runner's `/open-app`, which hangs until Foundation's default 60 s `URLRequest` timeout
fires — surfacing as `The request timed out.` with no indication that the real problem is
"this app is not installed". The same happens for `open_app("com.apple.mobilenotes")`: the dict is
keyed by *names*, so a bundle ID never matches and is likewise passed through unresolved.

This is the single highest-value fix: an unresolvable app name must fail **fast and explicitly**
("app 'Notes' is not installed; available: …"), not hang for a minute.

### 3. The agent's app list is full of harness/system noise (explains the SyncUps misfire — CONFIRMED)
Actual `CFBundleName` list the agent sees on this device:
```
AegirProxyApp, AssistiveTouch, CarPlay, CommandAndControl, Contacts, EscrowSecurityAlert, Files,
Fitness, FullKeyboardAccess, Health, IosUnitTests, KaleidoscopePosterApp, LiveTranscriptionUI, Maps,
MobileCal, MobileSMS, MobileSafari, News, Passwords, Photos, Preview, PridePosterApp,
QaltiUITests-Runner, Reminders, Settings, Shortcuts, ShortcutsActions, SpringBoard, UnityPosterApp,
VoiceOverTouch, Wallet, Watch, Web, Xcode Previews, touch_passthrough_demo
```
`QaltiUITests-Runner` — Qalti's **own test harness** — is right there as a normal candidate, which
fully explains the `gpt-4.1` SyncUps run picking `open_app("QaltiUITests-Ru...")`. Names are also
raw bundle-ish names (`MobileSMS`, `MobileCal`, `MobileSafari`) rather than user-facing labels
(Messages, Calendar, Safari), so an LLM matching on human names is being set up to fail.

### 4. Qalti's GUI app spawns an `idb_companion` process every ~1-2 seconds, forever (new finding)
A long-running Qalti GUI instance (pid 652, up **1 day 8 h**) was observed spawning a **fresh**
`.../Qalti.app/Contents/Resources/simulatorbinaries/bin/idb_companion --list 1` process every
1-2 seconds continuously (sampled: distinct PIDs 53202 → 53649 → 53843 → 53876 → 53967 within
seconds). Correlated state: **200** accumulated `CoreSimulator/.../Runtimes/...` processes, and
load average **44 (5 min) on a 10-core machine while the CPU was 78 % idle** — i.e. a large backlog
of blocked, short-lived processes hammering the shared CoreSimulator daemons.

This is a Qalti-side device-polling loop, is present **without** any other project involved, and is
a plausible contributor to the *original* machine's "CoreSimulatorService is flaky / simdiskimaged
crashed" symptoms that were previously attributed to other projects. Quit the Qalti GUI app before
running CLI matrices, and treat the polling interval as a bug to fix.


### Revised status of the earlier hypotheses
| # | Hypothesis | Status after 2026-07-28 |
|---|---|---|
| 1 | Bundle resolution silently passes garbage downstream | **CONFIRMED** — root cause of the opaque timeout |
| 2 | On-device runner `/open-app` handler hangs | Partly implicated: it hangs *given a bogus bundle ID*. Should reject unknown IDs fast. Still unread. |
| 3 | idb gRPC `list_apps` hangs | **Not supported** — `list_apps` returns fine and fast in all observations |
| 4 | Stale/broken gRPC connection | **Not supported** on the clean machine |
| 5 | Duplicate `FBProcess` class warning is harmful | **Not supported** — warning still present while other apps launch perfectly |
| — | Simulator contention (2026-07-27) | **Superseded** as primary cause: symptom reproduces on a dedicated, uncontended machine. Was real on the old machine, but not the explanation. |

### Next steps (ranked)
1. **Fix the fixture.** DONE 2026-07-28: replaced by `tests/reminders_create_and_verify.test`
   (`scripts/run_notes_model_matrix.sh` now points at it). Reminders was chosen over
   Contacts/Settings/Safari because it supports the same create-item-then-verify shape as the
   original Notes scenario. Verified: `com.apple.reminders` is registered
   (`ApplicationType = System`, `CFBundleDisplayName = Reminders`) and launches 3/3 in ~1.1 s, on
   both the long-lived and a freshly created device. It also resolves through **both** of Qalti's
   lookup paths — idb reports `CFBundleName = Reminders`, and `"Reminders": "com.apple.reminders"`
   is in the hardcoded dict at `AppBundleResolver.swift:56` — so it is immune to the class of
   resolution failure described in finding 2.

   Reminders does show interstitials: **"Welcome to Reminders" / Continue** on a fresh device, and
   **"Enable iCloud Syncing?" / Not Now** on an already-used one. These are deliberately left for
   the agent to handle rather than pre-cleared — Qalti is expected to navigate popups, and its own
   grading rubric explicitly anticipates them (`Prompts.swift:599`, "had to navigate through
   unexpected screens or popups" → *pass with comments*). The fixture includes an explicit
   "if a welcome screen or an iCloud syncing prompt appears, dismiss it and continue" step so that
   handling them counts as following the flow (**pass**) rather than as an unplanned adaptation
   (**pass with comments**) — which matters because that verdict string is the matrix's signal.
   The old `tests/notes_create_and_verify.test` is left in place but must not be used.
2. **Make unresolved app names fail fast.** Change `AppBundleResolver.resolveBundle` to return an
   optional/`Result` instead of echoing the input (`AppBundleResolver.swift:72-79`), and have
   `open_app` return a clear tool error listing available apps. Verify with a deliberate
   `open_app("NoSuchApp")` — it must fail in <1 s with a useful message.
3. **Add explicit deadlines** to the `/open-app` `URLRequest` (`IOSRuntimeRequestBuilder.swift:37-57`)
   and the idb gRPC calls (`idb.swift:677-712`) so any future hang fails fast with a specific error.
4. **Filter and humanize the app list** shown to the agent: drop `QaltiUITests-Runner`, `SpringBoard`,
   `IosUnitTests`, `*PosterApp`, `AegirProxyApp`, `EscrowSecurityAlert` etc., and map raw names to
   user-facing labels (`MobileSMS` → Messages, `MobileCal` → Calendar, `MobileSafari` → Safari).
5. **Fix the idb_companion polling storm** in the GUI app (finding 4) — throttle/cache the device
   list instead of respawning a process per second.
6. Only after 1-4: re-run the model matrix with the Qalti GUI quit, on a freshly booted dedicated
   simulator, and read verdicts from the report JSON's `testResult`.

### End-to-end verification 2026-07-29 — PASSES

`Qalti cli tests/reminders_create_and_verify.test --model gpt-4.1 --udid AFB3DA76-…` run on the
iOS 26.2 iPhone 16e, **concurrently with an unrelated heavy test matrix on the same machine**
(deliberately not stopped, to prove contention is not the blocker). Completed in **~80 s over 6
iterations, zero timeouts**
(`grep -c 'timed out'` on the run log = 0):

```
#01 open_app(app_name="Reminders")                                    <- succeeded, no timeout
#02 tap("Close 'Sync Reminders with iCloud' X button")                <- popup handled unprompted
#03 tap("Blue + button in bottom right corner")
#04 input(text="Qalti smoke test reminder")
#05 tap("Blue checkmark button in upper right corner")
#06 tap("Reminders list row with blue icon")
```

Report verdict (from `testResult`, not the CLI banner):
`"test_result": "pass"`, `"test_objective_achieved": true`, `"steps_followed_exactly": true`,
`"adaptations_made": []`. Independently confirmed by screenshotting the simulator afterwards — the
reminder "Qalti smoke test reminder" is genuinely present in the list, so this is not just the
model's self-report.

This closes the investigation's core question. It confirms, in one run: (a) `open_app` works
normally once the target app actually exists — the original bug was the impossible Notes fixture,
not the tooling; (b) Qalti does handle interstitial popups autonomously, as designed; (c) with the
dismissal written as an explicit step, popup handling grades as a clean **pass** rather than
*pass with comments* (`Prompts.swift:599`), preserving the matrix's signal; and (d) a busy machine
running an unrelated parallel 4-simulator matrix does **not** by itself cause the failure.

Still worth fixing regardless (findings 2-5 above): the resolver's silent fallthrough, the missing
HTTP/gRPC deadlines, the noisy app list, and the GUI's `idb_companion` respawn loop.

### Fixes applied + full matrix re-run 2026-07-29 — INVESTIGATION CLOSED

**Code fixes** (built clean, `xcodeproject/DerivedData_local`):

- `AppBundleResolver.swift` — rewritten. Adds `resolve(_:) -> Resolution`
  (`.resolved` / `.notInstalled(requested:available:)` / `.listUnavailable`) so a missing app is
  reported explicitly instead of the raw input being echoed back as a fake bundle ID. Also indexes
  the catalogue **by bundle ID as well as by display name** (kept in a separate map, because
  `normalizeAppKey` strips a trailing "app" and would corrupt IDs like `com.apple.DocumentsApp`),
  so `open_app("com.apple.reminders")` now resolves too. `resolveBundle(for:)` is retained with its
  old lenient behaviour for the `DeviceAdministration` call sites.
- `IOSRuntime.openApp` — uses `resolve(_:)` and fails immediately with that message.
- `idb.swift` `listApps` — the unbounded `semaphore.wait()` now has a **20 s** deadline and throws
  a specific "idb_companion is not responding" error rather than blocking forever.
- `IOSRuntimeRequestBuilder` — every runner request now carries an **explicit** `timeoutInterval`
  (60 s openApp/openURL, 45 s hierarchy, 30 s everything else) instead of silently inheriting
  Foundation's 60 s default.

**Verified:** `open_app("NoSuchAppXYZ")` now fails in **0.2 s** (was ~60 s), and the agent receives
an actionable tool response —
`{"success":false,"app_name":"NoSuchAppXYZ","error":"App 'NoSuchAppXYZ' is not installed on this device. Installed apps: AegirProxyApp, AssistiveTouch, Bridge, Calendar, …"}`
— which it correctly interpreted ("I verified … this app is not installed").

**Full 10-model matrix** on `tests/reminders_create_and_verify.test`, iOS 26.2 `AFB3DA76…`:

| Model | Verdict |
|---|---|
| gpt-4.1 | pass with comments |
| claude-4-sonnet | pass |
| claude-haiku-4.5 | pass |
| gpt-5 | pass |
| gpt-5-mini | pass |
| gpt-5-nano | pass |
| gemini-2.5-pro | no report — decoding bug (`keyNotFound: 'text'` at `choices[0].delta.rea…`) |
| gemini-3-flash-preview | no report — decoding bug (`dataCorrupted` at `service_tier`) |
| gemini-3-pro-preview | no report — stale model ID, HTTP error from OpenRouter |
| grok-4 | no report — stale model ID, HTTP error from OpenRouter |

**6 of 6 models that could reach OpenRouter passed — previously 0 of 6.** Across all ten runs:
`grep -c 'timed out'` = **0**. The four failures are the two *pre-existing, separately-tracked*
issues (two stale model IDs, two response-decoding bugs) and are unrelated to `open_app`.

`scripts/run_notes_model_matrix.sh` also had its summary fixed: because `--report-path` is parsed
but never wired to the save path, it was reading report files that are never written and would
have printed "NO REPORT" for all ten. It now recovers the real path from each run's
`Report saved to:` line and prefers the report's structured `testResult`.

### Unit tests added 2026-07-29 — and they immediately found another bug

The changed code had **no unit coverage at all**: there was no `AppBundleResolverTests`, no test of
`IOSRuntime.openApp`, and zero assertions on `timeoutInterval` anywhere in the repo. Worse,
`MockAppBundleResolver` overrode `resolveBundle(for:)` to `return app` — the mock enshrined the
exact silent-fallthrough bug this investigation was about, so every test using it was asserting the
broken behaviour was fine. That is a large part of why the bug survived so long.

Added `QaltiUnitTests/IOSRuntime/AppBundleResolverTests.swift` (16 tests) covering: resolution by
display name (case/space-insensitive, trailing-"app" tolerant), the new resolution by bundle ID
(including that `com.apple.DocumentsApp` is not truncated to `…Documents`), `.notInstalled` with a
populated available-apps list, the failure message naming both the app and the alternatives,
`.listUnavailable` being *distinct* from "not installed" when the device is unreachable, error
capture, the system-app fallback, and the deliberate lenient behaviour retained in
`resolveBundle(for:)`. Plus one test in `IOSRuntimeRequestBuilderTests` pinning the per-command
deadlines. `MockAppBundleResolver` now carries a comment saying its passthrough is a test
convenience and explicitly *not* a model of production behaviour.

**A new pre-existing bug surfaced immediately.** `test_resolve_idbEntryWins_overSystemAppFallback`
failed: the hardcoded system-app dictionary was applied *after* the idb results and overwrote them
unconditionally, despite its own comment describing it as a fallback ("they might not be returned
by IDB"). An app genuinely installed on the device and reported by idb under a name that collides
with the table — say a bundled app called "Settings" — would silently resolve to
`com.apple.Preferences` and launch the wrong app. That is the same failure mode as the SyncUps run
opening `QaltiUITests-Runner`. Fixed: system entries now only fill gaps in the name index and never
clobber a live idb entry.

Suite result: **156 tests, 0 failures.**

**Branches consolidated + verified 2026-07-29.** `fix/open-app-timeout` was based on `main` and so
lacked the CLI auth-key fix living on `feature/openrouter_model_tooling` — every CLI run there died
with an OpenRouter 401 before reaching the simulator, which blocked end-to-end verification of the
resolution-ordering change. Rather than split commit `e0b9e93` (which mixes the auth fix with
OpenRouter tooling), `fix/open-app-timeout` was merged into `feature/openrouter_model_tooling`
(merge `c1830ab`, no conflicts) so all the work lives on one branch. Re-verified there:

- unit suite: **156 tests, 0 failures**
- Reminders fixture, gpt-4.1, iOS 26.2 `AFB3DA76…`: **`test_result: "pass"`,
  `test_objective_achieved: true`, 0 adaptations, 0 timeouts**
- `open_app("NoSuchAppXYZ")`: still fails immediately with the installed-app list, 0 timeouts

Both the fast-failure behaviour and normal resolution therefore hold with the system-app ordering
fix in place.

### Fixture made sound + matrix re-run with app-side ground truth 2026-07-29

The first Reminders matrix proved the six passing models *claimed* success, but the scenario could
not actually prove it: nothing cleans up, so after several runs the list held 9 identical
`"Qalti smoke test reminder"` rows and the final step — "verify a reminder containing <fixed text>
appears" — could be satisfied by a reminder some earlier run created. gpt-4.1 even noticed
("Observed the presence of a duplicate reminder with the same text"). A model that skipped creation
entirely and jumped to verification would still have passed. For a benchmark whose purpose is
ranking models, that is a hole.

Fixed by making the fixture a template: `tests/reminders_create_and_verify.test` now types and
verifies `{{RUN_ID}}`, and `run_notes_model_matrix.sh` substitutes a fresh `run-<6 hex>` token per
model, writes the generated fixture beside the log, and records the mapping in `run_ids.txt`.
Verification can now only succeed on the reminder that run itself created. The script also gained a
ground-truth stage that copies the Reminders CoreData store **with its `-wal`** (recent rows live
there, not in the main file) and checks each token actually reached the app.

Re-run results — agent verdict vs. what is really in the app:

| Model | Run id | Agent verdict | In app? |
|---|---|---|---|
| gpt-4.1 | run-b150a8 | pass with comments | IN APP |
| claude-4-sonnet | run-1537cd | pass | IN APP |
| claude-haiku-4.5 | run-474c7d | pass | IN APP |
| gpt-5-mini | run-acbf2a | pass | IN APP |
| gpt-5 | run-4f635d | pass | IN APP |
| gemini-2.5-pro | run-985776 | no report (decoding bug) | not in app |
| gemini-3-flash-preview | run-b3d6a0 | no report (decoding bug) | not in app |
| gemini-3-pro-preview | run-f2f6d9 | no report (stale ID) | not in app |
| grok-4 | run-906996 | no report (stale ID) | not in app |
| gpt-5-nano | run-9126e1 | no report (max iterations) | not in app |

**Verdict and ground truth agree in all ten cases** — no model claimed an objective it had not
actually achieved. The five passes are corroborated by exactly one reminder carrying that run's own
token.

Two notes on the differences from the first run:

- **gpt-5-nano is flaky, not broken.** It passed the first matrix (~9 min) but here ran 25m42s and
  died on "Max iterations reached without completion or valid JSON result" with only **one** valid
  action across 50 iterations — it kept failing to emit a usable tool call. Worth re-running before
  drawing conclusions about it. Mid-run it looked hung; sampling the process showed it inside
  `IOSAgent.streamResult` with the SSE parser actively consuming data, i.e. genuinely streaming.
  Note the 240s LLM timeout is an *idle* timeout, so a slow-but-alive stream never trips it — do
  not kill a run that looks stalled without sampling it first.
- **gemini-3-flash-preview created nothing this time**, where in the first matrix it got as far as
  typing the text before the decoding bug killed it. It fails at whatever point the malformed
  response arrives, so "no report" says nothing about whether the model can drive the UI.

Run under heavy concurrent load from an unrelated test matrix on the same machine (load average
50-69), on a simulator that matrix does not use — verified before launching.

## Repro environment details (for reference)

- macOS 26.4.1 (25E253), Xcode 26.2 (17C52 toolchain)
- Original repro on "iPhone 17" / iOS 26.0; post-fix verification on "iPhone 16e" / iOS 26.2.
  Resolve a UDID with `xcrun simctl list devices | grep Booted` rather than reusing one from this
  document, and check that only the simulator you intend is booted.
- `idb_companion` binary reports "Built at Jul 14 2025 23:10:15", architecture arm64
- Qalti built from `xcodeproject/Qalti.xcodeproj`, scheme `Qalti`, Debug config, via
  `xcodebuild ... -derivedDataPath xcodeproject/DerivedData_local build`
- Simulator runner artifacts must be (re)generated once via
  `cd xcodeproject && bash ./scripts/archive_simulator_runner.sh` before the CLI's
  `xcodebuild test-without-building` pipeline can connect at all — a one-time setup gap worth
  knowing about when starting from a fresh checkout
