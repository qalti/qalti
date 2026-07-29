#!/usr/bin/env python3
"""One-off: extract real per-model verdicts from run_notes_model_matrix.sh log files,
by following each log's own "Report saved to:" line (since --report-path doesn't work,
see PA-015 continuation notes) to the actual JSON report under ~/Documents/Qalti/Runs/.
Uses the report's top-level "testResult" field (runSucceeded is force-set true in CLI mode
and is not a trustworthy verdict)."""
import json
import re
import sys
from pathlib import Path

MODELS_IN_ORDER = [
    "gpt-4.1",
    "claude-4-sonnet",
    "gemini-2.5-pro",
    "gemini-3-pro-preview",
    "gemini-3-flash-preview",
    "claude-haiku-4.5",
    "grok-4",
    "gpt-5-mini",
    "gpt-5-nano",
    "gpt-5",
]

log_dir = Path(sys.argv[1])

for model in MODELS_IN_ORDER:
    log_path = log_dir / f"{model}.log"
    if not log_path.exists():
        print(f"{model:25s} NO LOG FILE")
        continue
    text = log_path.read_text()

    m = re.search(r"Report saved to: (\S+\.json)", text)
    if not m:
        fail_m = re.search(r"Test (?:execution failed|failed): (.+)", text)
        if fail_m:
            print(f"{model:25s} RUN-LEVEL FAILURE: {fail_m.group(1)[:180]}")
        else:
            print(f"{model:25s} NO REPORT PATH FOUND IN LOG")
        continue

    report_path = Path(m.group(1))
    if not report_path.exists():
        print(f"{model:25s} REPORT FILE MISSING: {report_path}")
        continue

    try:
        data = json.loads(report_path.read_text())
    except Exception as e:
        print(f"{model:25s} UNREADABLE REPORT ({e})")
        continue

    test_result = data.get("testResult")
    if test_result:
        verdict = f"{test_result.get('test_result', '?')} (objective_achieved={test_result.get('test_objective_achieved', '?')}) - {test_result.get('comments', '')[:120]}"
    else:
        verdict = "UNKNOWN (no testResult field)"

    print(f"{model:25s} {verdict}")
