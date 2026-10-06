import Foundation

/// Optional integration with simslim (https://github.com/MobAI-App/simslim), a tool that
/// reduces a booted iOS Simulator's memory footprint by disabling daemons it doesn't need.
///
/// Never a hard dependency: if the binary isn't found, worker simulators just stay stock and
/// the run proceeds exactly as it did before this integration existed.
enum SimslimService {
    /// Resolves the simslim binary path. Checks `QALTI_SIMSLIM_PATH` first (for pinning a
    /// specific build), then falls back to whatever `simslim` resolves to on PATH.
    static func locateBinary() -> String? {
        if let pinned = ProcessInfo.processInfo.environment["QALTI_SIMSLIM_PATH"], !pinned.isEmpty {
            if FileManager.default.isExecutableFile(atPath: pinned) {
                return pinned
            }
            Log.i("[Scheduler] QALTI_SIMSLIM_PATH=\(pinned) is not executable; falling back to PATH")
        }
        guard let (code, out, _) = try? ProcessUtils.runProcess("/usr/bin/which", ["simslim"]),
              code == 0 else {
            return nil
        }
        let path = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    /// Slims already-booted worker simulators in place, best-effort. Does nothing if `enabled`
    /// is false or the binary can't be found; a per-device failure is logged and skipped rather
    /// than aborting the run, since a worker that stays stock is still usable.
    static func slimWorkersIfRequested(udids: [String], enabled: Bool) {
        guard enabled else { return }
        guard let binary = locateBinary() else {
            Log.i("[Scheduler] --slim-workers was set but the simslim binary was not found (checked QALTI_SIMSLIM_PATH and PATH); continuing with stock simulators")
            return
        }
        Log.v("[Scheduler] Slimming \(udids.count) worker simulator(s) via \(binary)")
        let slimmedCount = DispatchQueue(label: "com.qalti.simslim.count")
        var slimmed = 0
        let group = DispatchGroup()
        for udid in udids {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                let (code, _, err) = (try? ProcessUtils.runProcess(binary, ["on", "--no-reboot", udid])) ?? (-1, "", "simslim process failed to launch")
                if code == 0 {
                    slimmedCount.sync { slimmed += 1 }
                    Log.v("[Scheduler] Slimmed \(udid)")
                } else {
                    Log.i("[Scheduler] simslim failed on \(udid), leaving it stock: \(err.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            }
        }
        group.wait()
        Log.i("[Scheduler] Slimmed \(slimmed)/\(udids.count) worker simulator(s)")
    }
}
