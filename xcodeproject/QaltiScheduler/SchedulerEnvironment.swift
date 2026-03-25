import Foundation

enum SchedulerEnvironment {
    static func detectQaltiAppPath(verbose: Bool) -> URL? {
        // 1) Prefer Qalti.app located next to the scheduler binary (e.g. DerivedData/.../Build/Products/Debug or Release)
        if let execURL = Bundle.main.executableURL {
            let siblingApp = execURL.deletingLastPathComponent().appendingPathComponent("Qalti.app")
            if FileManager.default.fileExists(atPath: siblingApp.path) {
                if verbose { Log.i("[Scheduler] Using Qalti.app next to scheduler: \(siblingApp.path)") }
                return siblingApp
            }
        } else if let arg0 = CommandLine.arguments.first, !arg0.isEmpty {
            let argURL = URL(fileURLWithPath: arg0).standardizedFileURL
            if FileManager.default.fileExists(atPath: argURL.path) {
                let siblingApp = argURL.deletingLastPathComponent().appendingPathComponent("Qalti.app")
                if FileManager.default.fileExists(atPath: siblingApp.path) {
                    if verbose { Log.i("[Scheduler] Using Qalti.app next to scheduler: \(siblingApp.path)") }
                    return siblingApp
                }
            }
        }

        // 2) Try current working directory
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let local = cwd.appendingPathComponent("Qalti.app")
        if FileManager.default.fileExists(atPath: local.path) {
            Log.v("[Scheduler] Using local Qalti.app: \(local.path)")
            return local
        }

        // 3) Fallback to /Applications
        let applications = URL(fileURLWithPath: "/Applications").appendingPathComponent("Qalti.app")
        if FileManager.default.fileExists(atPath: applications.path) {
            Log.v("[Scheduler] Using /Applications/Qalti.app")
            return applications
        }
        Log.v("[Scheduler] Qalti.app not found locally or in /Applications")
        return nil
    }
}
