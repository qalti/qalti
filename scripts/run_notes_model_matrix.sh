#!/usr/bin/env bash
# Runs tests/reminders_create_and_verify.test once per model in Qalti's TestRunner.AvailableModel
# list, to spot-check that every hardcoded model ID still resolves against a live OpenRouter
# call. grok-4 and gemini-3-pro-preview are expected to fail (see PA-015 continuation notes) —
# they're intentionally left in the matrix, unmodified, to document the live failure.
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
# launchable. See OPEN_APP_TIMEOUT_INVESTIGATION.md, "UPDATE 2026-07-28".
TEST_FILE="tests/reminders_create_and_verify.test"
REPORT_DIR="scripts/output/notes_model_matrix_$(date +%Y%m%d_%H%M%S)"
DEVICE_UDID="${QALTI_SIM_UDID:?Set QALTI_SIM_UDID to a booted simulator UDID, e.g. from: xcrun simctl list devices | grep Booted}"

# Order: gpt-4.1 first, claude-sonnet-4 second, then the rest of TestRunner.AvailableModel.allCases.
MODELS=(
  "gpt-4.1"
  "claude-4-sonnet"
  "gemini-2.5-pro"
  "gemini-3-pro-preview"   # expected to fail: stale ID, see memory/stale_openrouter_model_ids.md
  "gemini-3-flash-preview"
  "claude-haiku-4.5"
  "grok-4"                 # expected to fail: stale ID, see memory/stale_openrouter_model_ids.md
  "gpt-5-mini"
  "gpt-5-nano"
  "gpt-5"
)

mkdir -p "$REPORT_DIR"

for model in "${MODELS[@]}"; do
  safe_name="${model//\//_}"
  echo "=== Running with --model $model ==="
  "$QALTI_BIN" cli "$TEST_FILE" \
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
