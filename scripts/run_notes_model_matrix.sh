#!/usr/bin/env bash
# Runs tests/reminders_create_and_verify.test once per model in Qalti's TestRunner.AvailableModel
# list, to spot-check that every hardcoded model ID still resolves against a live OpenRouter call.
# The list below must stay in sync with TestRunner.AvailableModel.allCases; see
# docs/openrouter_models.md for which IDs are known live vs. known dead.
#
# NOTE: Qalti's CLI mode force-overrides an agent-decided failure to "success" at the top
# level (TestRunner.swift, "forcing SUCCESS to match legacy behavior"), so neither the CLI's
# own exit code nor its printed "Test completed successfully" line is a trustworthy verdict.
# The real per-run result is extracted below from the report JSON's embedded assistant JSON
# block (test_result / test_objective_achieved), not from the top-level runSucceeded field.
set -uo pipefail

QALTI_BIN="xcodeproject/DerivedData_local/Build/Products/Debug/Qalti.app/Contents/MacOS/Qalti"
# NOTE: was tests/notes_create_and_verify.test until 2026-07-28. Notes (com.apple.mobilenotes) is
# not registered/launchable on iOS 26.x simulators at all — even plain `xcrun simctl launch` fails —
# so that fixture was impossible and every model "failed" it identically. Reminders is verified
# launchable. See docs/investigations/open-app-timeout.md, "UPDATE 2026-07-28".
TEST_FILE="tests/reminders_create_and_verify.test"
REPORT_DIR="scripts/output/notes_model_matrix_$(date +%Y%m%d_%H%M%S)"
DEVICE_UDID="${QALTI_SIM_UDID:?Set QALTI_SIM_UDID to a booted simulator UDID, e.g. from: xcrun simctl list devices | grep Booted}"
: "${OPENROUTER_API_KEY:?Set OPENROUTER_API_KEY to an OpenRouter key (https://openrouter.ai/keys)}"

# Order: gpt-4.1 first, claude-sonnet-4 second, then the rest of TestRunner.AvailableModel.allCases.
# Known-dead IDs (grok-4, gemini-3-pro-preview — see docs/openrouter_models.md) are deliberately
# NOT listed here: they would make this matrix permanently red and hide real regressions. Their
# live replacements are covered instead.
MODELS=(
  "gpt-4.1"
  "claude-4-sonnet"
  "gemini-2.5-pro"
  "gemini-3-flash-preview"
  "claude-haiku-4.5"
  "gpt-5-mini"
  "gpt-5-nano"
  "gpt-5"
  "grok-4.5"
  "gemini-3.1-pro-preview"
)

mkdir -p "$REPORT_DIR"

> "$REPORT_DIR/run_ids.txt"

for model in "${MODELS[@]}"; do
  safe_name="${model//\//_}"

  # The fixture is a template: {{RUN_ID}} is replaced with a token unique to this run.
  # Without it the scenario is unsound as a benchmark — the reminders list is never cleaned up, so
  # "verify a reminder containing <fixed text> appears" can be satisfied by a reminder some earlier
  # run created, and a model that skipped creation entirely would still pass.
  run_id="run-$(openssl rand -hex 3)"
  run_test="$REPORT_DIR/${safe_name}.test"
  sed "s/{{RUN_ID}}/$run_id/g" "$TEST_FILE" > "$run_test"
  echo "$model $run_id" >> "$REPORT_DIR/run_ids.txt"

  echo "=== Running with --model $model (run id: $run_id) ==="
  "$QALTI_BIN" cli "$run_test" \
    --token "$OPENROUTER_API_KEY" \
    --model "$model" \
    --udid "$DEVICE_UDID" \
    --report-path "$REPORT_DIR/${safe_name}.json" \
    --log-level info \
    2>&1 | tee "$REPORT_DIR/${safe_name}.log"
  exit_code=${PIPESTATUS[0]}
  echo "=== Done: $model (qalti exit code: $exit_code) ==="
  echo
done

echo "All runs complete. Reports in $REPORT_DIR"
echo
echo "=== Summary (real agent verdict, not the CLI's forced-success banner) ==="
python3 - "$REPORT_DIR" "${MODELS[@]}" <<'EOF'
import json, re, sys, pathlib

report_dir = pathlib.Path(sys.argv[1])
models = sys.argv[2:]

for model in models:
    safe_name = model.replace("/", "_")

    # --report-path is parsed but never wired to the actual save path, so the report does NOT
    # land in REPORT_DIR. The run's own stdout is the only reliable pointer to it.
    log = report_dir / f"{safe_name}.log"
    path = None
    if log.exists():
        found = re.findall(r"Report saved to:\s*(\S+)", log.read_text(errors="replace"))
        if found:
            path = pathlib.Path(found[-1])

    if path is None or not path.exists():
        print(f"{model:25s} NO REPORT (qalti likely crashed before writing one)")
        continue
    try:
        data = json.loads(path.read_text())
    except Exception as e:
        print(f"{model:25s} UNREADABLE REPORT ({e})")
        continue

    # Prefer the structured verdict; fall back to the embedded assistant JSON block.
    verdict = None
    tr = data.get("testResult")
    if isinstance(tr, dict) and tr.get("test_result"):
        verdict = f"{tr.get('test_result')} (objective_achieved={tr.get('test_objective_achieved', '?')})"

    if verdict is None:
        history = data.get("runHistory", [])
        last_assistant = None
        for msg in history:
            if msg.get("role") == "assistant":
                last_assistant = msg

        verdict = "UNKNOWN (no assistant JSON found)"
        if last_assistant:
            content = last_assistant.get("content", "")
            m = re.search(r"```json\s*(\{.*?\})\s*```", content, re.S)
            if m:
                try:
                    parsed = json.loads(m.group(1))
                    verdict = f"{parsed.get('test_result', '?')} (objective_achieved={parsed.get('test_objective_achieved', '?')})"
                except Exception:
                    pass

    run_failure = data.get("runFailureReason")
    if run_failure:
        verdict = f"RUN-LEVEL FAILURE: {run_failure[:150]}"

    print(f"{model:25s} {verdict}")
EOF

echo
echo "=== Ground truth: did the reminder actually reach the app? ==="
echo "(reads the Reminders store on the simulator — independent of what the agent claimed)"
python3 - "$DEVICE_UDID" "$REPORT_DIR" <<'EOF'
import glob, os, pathlib, shutil, sqlite3, sys, tempfile

udid, report_dir = sys.argv[1], pathlib.Path(sys.argv[2])

pattern = os.path.expanduser(
    f"~/Library/Developer/CoreSimulator/Devices/{udid}"
    "/data/Containers/Shared/AppGroup/*/Container_v1/Stores/Data-*.sqlite"
)

# Copy each candidate store (plus its WAL) before opening: rows written by a recent run often live
# only in the -wal, and we must not touch the live database the simulator is using.
tmp = tempfile.mkdtemp()
titles = []
for store in glob.glob(pattern):
    for suffix in ("", "-wal", "-shm"):
        if os.path.exists(store + suffix):
            shutil.copy2(store + suffix, tmp)
    copied = os.path.join(tmp, os.path.basename(store))
    try:
        con = sqlite3.connect(copied)
        titles += [r[0] for r in con.execute(
            "SELECT ZTITLE FROM ZREMCDREMINDER WHERE ZTITLE IS NOT NULL")]
        con.close()
    except sqlite3.Error:
        continue  # not the reminders store
shutil.rmtree(tmp, ignore_errors=True)

run_ids = report_dir / "run_ids.txt"
if not run_ids.exists():
    print("  (no run_ids.txt — nothing to check)")
    raise SystemExit

for line in run_ids.read_text().split("\n"):
    if not line.strip():
        continue
    model, run_id = line.split()
    found = sum(1 for t in titles if run_id in t)
    if found == 1:
        status = "IN APP"
    elif found == 0:
        status = "NOT IN APP  <- nothing was created"
    else:
        status = f"IN APP x{found}  <- created more than once"
    print(f"{model:25s} {run_id:12s} {status}")
EOF
