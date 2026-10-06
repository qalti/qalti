import Foundation

// Smoke-test driver for SimslimService. Run via scripts/smoke_test_simslim.sh, which compiles
// this file together with the real production sources (SimslimService.swift, ProcessUtils.swift,
// Logger.swift) so there's no duplicated logic to drift out of sync. Exercises
// locateBinary()'s PATH/pinned-path fallback and slimWorkersIfRequested()'s parallelism and
// result counting against a fake `simslim` shim.

var failures = 0

func check(_ name: String, _ condition: Bool) {
    if condition {
        print("PASS: \(name)")
    } else {
        print("FAIL: \(name)")
        failures += 1
    }
}

func captureStdout(_ body: () -> Void) -> String {
    fflush(stdout)
    let pipe = Pipe()
    let originalStdout = dup(1)
    dup2(pipe.fileHandleForWriting.fileDescriptor, 1)
    body()
    fflush(stdout)
    pipe.fileHandleForWriting.closeFile()
    dup2(originalStdout, 1)
    close(originalStdout)
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}

// --- Fixture: a fake simslim binary controlled via env vars ---
// SIMSLIM_SLEEP: seconds to sleep before exiting (used to prove parallelism)
// SIMSLIM_FAIL_UDIDS: comma-separated udids that should exit non-zero
let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("simslim_smoke_\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
let fakeSimslimPath = tmpDir.appendingPathComponent("simslim").path
let fakeSimslimScript = """
#!/bin/bash
udid="${*: -1}"
sleep "${SIMSLIM_SLEEP:-0}"
if [[ ",${SIMSLIM_FAIL_UDIDS:-}," == *",$udid,"* ]]; then
  echo "forced failure for $udid" >&2
  exit 1
fi
exit 0
"""
try! fakeSimslimScript.write(toFile: fakeSimslimPath, atomically: true, encoding: .utf8)
try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeSimslimPath)

let originalPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
setenv("PATH", "\(tmpDir.path):\(originalPath)", 1)
unsetenv("QALTI_SIMSLIM_PATH")
unsetenv("SIMSLIM_SLEEP")
unsetenv("SIMSLIM_FAIL_UDIDS")

// Test 1: nothing pinned, resolves via PATH.
do {
    let resolved = SimslimService.locateBinary()
    check("locateBinary() resolves fake simslim via PATH", resolved == fakeSimslimPath)
}

// Test 2: QALTI_SIMSLIM_PATH points at a non-executable/missing file -> falls back to PATH
// and logs a warning (even without verbose mode).
do {
    setenv("QALTI_SIMSLIM_PATH", "/no/such/binary-\(UUID().uuidString)", 1)
    var resolved: String?
    let output = captureStdout {
        resolved = SimslimService.locateBinary()
    }
    check("locateBinary() falls back to PATH when pinned path is invalid", resolved == fakeSimslimPath)
    check("invalid QALTI_SIMSLIM_PATH logs a fallback warning", output.contains("is not executable; falling back to PATH"))
    unsetenv("QALTI_SIMSLIM_PATH")
}

// Test 3: QALTI_SIMSLIM_PATH points at a valid executable -> used directly, no warning.
do {
    setenv("QALTI_SIMSLIM_PATH", fakeSimslimPath, 1)
    var resolved: String?
    let output = captureStdout {
        resolved = SimslimService.locateBinary()
    }
    check("locateBinary() honors a valid pinned path", resolved == fakeSimslimPath)
    check("valid QALTI_SIMSLIM_PATH logs no fallback warning", !output.contains("falling back to PATH"))
    unsetenv("QALTI_SIMSLIM_PATH")
}

// Test 4: slimWorkersIfRequested(enabled: false) is a no-op.
do {
    let output = captureStdout {
        SimslimService.slimWorkersIfRequested(udids: ["udid-a"], enabled: false)
    }
    check("disabled slimWorkersIfRequested logs nothing", output.isEmpty)
}

// Test 5: slimming N workers runs in parallel, not sequentially.
do {
    let udids = (0..<6).map { "udid-\($0)" }
    setenv("SIMSLIM_SLEEP", "0.5", 1)
    let start = Date()
    _ = captureStdout {
        SimslimService.slimWorkersIfRequested(udids: udids, enabled: true)
    }
    let elapsed = Date().timeIntervalSince(start)
    check("slimming \(udids.count) workers at 0.5s each takes well under \(Double(udids.count) * 0.5)s serial time (took \(String(format: "%.2f", elapsed))s)", elapsed < 1.5)
    unsetenv("SIMSLIM_SLEEP")
}

// Test 6: per-device failures are counted correctly and don't abort the batch, even under
// concurrency (exercises the thread-safe counter).
do {
    let udids = (0..<10).map { "udid-\($0)" }
    let failing = Set(udids.enumerated().filter { $0.offset % 3 == 0 }.map { $0.element })
    setenv("SIMSLIM_FAIL_UDIDS", failing.joined(separator: ","), 1)
    let output = captureStdout {
        SimslimService.slimWorkersIfRequested(udids: udids, enabled: true)
    }
    let expectedSlimmed = udids.count - failing.count
    check("slimmed count matches expected successes under concurrency (\(expectedSlimmed)/\(udids.count))", output.contains("Slimmed \(expectedSlimmed)/\(udids.count) worker simulator(s)"))
    for udid in failing {
        check("failure for \(udid) is logged individually", output.contains("simslim failed on \(udid)"))
    }
    unsetenv("SIMSLIM_FAIL_UDIDS")
}

try? FileManager.default.removeItem(at: tmpDir)

if failures > 0 {
    print("\n\(failures) check(s) FAILED")
    exit(1)
} else {
    print("\nAll checks passed")
    exit(0)
}
