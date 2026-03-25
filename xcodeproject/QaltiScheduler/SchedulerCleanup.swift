import Foundation
import ArgumentParser 

enum SchedulerCleanup {
    static func performGlobalCleanupIfLeader(verbose: Bool) {
        if otherSchedulerInstancesExist() {
            Log.v("[Scheduler] Another scheduler instance detected; skipping global cleanup")
            return
        }
        Log.v("[Scheduler] Performing global orphan cleanup of QaltiWorker- simulators")
        do {
            let orphanUdids = try listQaltiWorkerSimulators()
            if orphanUdids.isEmpty {
                Log.v("[Scheduler] No QaltiWorker- simulators found for cleanup")
                return
            }
            try SimctlService.shutdownSimulators(udids: orphanUdids, verbose: verbose)
            try SimctlService.deleteSimulators(udids: orphanUdids, verbose: verbose)
        } catch {
            Log.v("[Scheduler] Global cleanup failed: \(error)")
        }
    }

    static func otherSchedulerInstancesExist() -> Bool {
        let currentPid = getpid()
        let (code, out, _) = try! ProcessUtils.runProcess("/usr/bin/pgrep", ["-x", "QaltiScheduler"])
        guard code == 0 else { return false }
        let pids = out
            .split(separator: "\n")
            .compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        for pid in pids where pid != currentPid {
            return true
        }
        return false
    }

    static func listQaltiWorkerSimulators() throws -> [String] {
        let (code, out, err) = try ProcessUtils.runProcess("/usr/bin/xcrun", ["simctl", "list", "-j", "devices"])
        guard code == 0 else { throw ValidationError("simctl devices failed: \(err)") }
        let decoded = try JSONDecoder().decode(SimctlDevicesRoot.self, from: Data(out.utf8))
        var udids: [String] = []
        for (_, devices) in decoded.devices {
            for d in devices {
                if d.name.hasPrefix("QaltiWorker-") {
                    udids.append(d.udid)
                }
            }
        }
        return udids
    }
}
