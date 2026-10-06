#!/bin/bash
# Compiles scripts/tests/simslim_smoke_test.swift against the real SimslimService production
# sources and runs it. QaltiScheduler has no XCTest target of its own, so this is the
# lightweight stand-in: no Xcode project changes, no mocked production code.
set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEDULER_DIR="$REPO_ROOT/xcodeproject/QaltiScheduler"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# swiftc only allows top-level statements in a file literally named main.swift.
cp "$REPO_ROOT/scripts/tests/simslim_smoke_test.swift" "$WORK_DIR/main.swift"

swiftc -O \
  "$SCHEDULER_DIR/SimslimService.swift" \
  "$SCHEDULER_DIR/ProcessUtils.swift" \
  "$SCHEDULER_DIR/Logger.swift" \
  "$WORK_DIR/main.swift" \
  -o "$WORK_DIR/simslim_smoke_test"

"$WORK_DIR/simslim_smoke_test"
