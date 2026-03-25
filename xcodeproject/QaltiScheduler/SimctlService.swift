import Foundation
import ArgumentParser

struct SimctlRuntimes: Decodable { let runtimes: [SimRuntime] }
struct SimRuntime: Decodable { let identifier: String; let name: String; let version: String; let isAvailable: Bool?; let availability: String? }
struct SimctlDevicesRoot: Decodable { let devices: [String: [SimDevice]] }
struct SimDevice: Decodable { let state: String?; let isAvailable: Bool?; let availability: String?; let name: String; let udid: String }
struct SimctlDeviceTypes: Decodable { let devicetypes: [SimDeviceType] }
struct SimDeviceType: Decodable { let name: String; let identifier: String }

enum SimctlService {
    static func findOrCreateBaseSimulator(deviceName: String, osVersion: String, verbose: Bool) throws -> (String, String) {
        let runtimeId = try findRuntimeIdentifier(osVersion: osVersion)
        if let device = try findDevice(named: deviceName, runtimeIdentifier: runtimeId) {
            return (device.udid, runtimeId)
        }
        let deviceTypeId = try findDeviceTypeIdentifier(deviceName: deviceName)
        let name = "QaltiBase-\(deviceName)-iOS\(osVersion)"
        let (code, out, err) = try ProcessUtils.runProcess("/usr/bin/xcrun", ["simctl", "create", name, deviceTypeId, runtimeId])
        guard code == 0 else { throw ValidationError("Failed to create simulator: \(err.trimmingCharacters(in: .whitespacesAndNewlines))") }
        let udid = out.trimmingCharacters(in: .whitespacesAndNewlines)
        Log.v("[Scheduler] Created base simulator: \(udid)")
        return (udid, runtimeId)
    }

    static func findRuntimeIdentifier(osVersion: String) throws -> String {
        let (code, out, err) = try ProcessUtils.runProcess("/usr/bin/xcrun", ["simctl", "list", "-j", "runtimes"])
        guard code == 0 else { throw ValidationError("simctl runtimes failed: \(err)") }
        let decoded = try JSONDecoder().decode(SimctlRuntimes.self, from: Data(out.utf8))
        let candidates = decoded.runtimes.filter { ($0.isAvailable ?? true) && $0.name.lowercased().contains("ios") }
        if let exact = candidates.first(where: { $0.version == osVersion }) { return exact.identifier }
        if let prefix = candidates.first(where: { $0.version.hasPrefix(osVersion) }) { return prefix.identifier }
        if let byName = candidates.first(where: { $0.name.contains(osVersion) }) { return byName.identifier }
        throw ValidationError("No available iOS runtime found for version \(osVersion)")
    }

    static func findDeviceTypeIdentifier(deviceName: String) throws -> String {
        let (code, out, err) = try ProcessUtils.runProcess("/usr/bin/xcrun", ["simctl", "list", "-j", "devicetypes"])
        guard code == 0 else { throw ValidationError("simctl devicetypes failed: \(err)") }
        let decoded = try JSONDecoder().decode(SimctlDeviceTypes.self, from: Data(out.utf8))
        guard let match = decoded.devicetypes.first(where: { $0.name == deviceName }) else {
            throw ValidationError("Device type not found: \(deviceName)")
        }
        return match.identifier
    }

    static func findDevice(named deviceName: String, runtimeIdentifier: String) throws -> SimDevice? {
        let (code, out, err) = try ProcessUtils.runProcess("/usr/bin/xcrun", ["simctl", "list", "-j", "devices"])
        guard code == 0 else { throw ValidationError("simctl devices failed: \(err)") }
        let decoded = try JSONDecoder().decode(SimctlDevicesRoot.self, from: Data(out.utf8))
        let list = decoded.devices[runtimeIdentifier] ?? []
        return list.first(where: { $0.name == deviceName && (($0.isAvailable ?? true) || ($0.availability == "(available)")) })
    }

    static func cloneSimulators(sourceUDID: String, count: Int, deviceName: String, osVersion: String, verbose: Bool) throws -> [String] {
        precondition(count > 0, "count must be > 0")
        var udids: [String] = []
        let stamp = Int(Date().timeIntervalSince1970)
        _ = try ProcessUtils.runProcess("/usr/bin/xcrun", ["simctl", "shutdown", sourceUDID])
        for i in 1...count {
            let name = "QaltiWorker-\(i)-\(deviceName)-iOS\(osVersion)-\(stamp)"
            let (code, out, err) = try ProcessUtils.runProcess("/usr/bin/xcrun", ["simctl", "clone", sourceUDID, name])
            guard code == 0 else { throw ValidationError("Failed to clone simulator: \(err.trimmingCharacters(in: .whitespacesAndNewlines))") }
            let udid = out.trimmingCharacters(in: .whitespacesAndNewlines)
            Log.v("[Scheduler] Cloned -> \(udid) (\(name))")
            udids.append(udid)
        }
        return udids
    }

    static func bootSimulators(udids: [String], verbose: Bool) throws {
        for udid in udids {
            Log.v("[Scheduler] Booting \(udid)...")
            _ = try? ProcessUtils.runProcess("/usr/bin/xcrun", ["simctl", "boot", udid])
            let (code, _, err) = try ProcessUtils.runProcess("/usr/bin/xcrun", ["simctl", "bootstatus", udid, "-b"])
            guard code == 0 else { throw ValidationError("Failed waiting for boot: \(err)") }
            Log.v("[Scheduler] Booted \(udid)")
        }
    }

    static func shutdownSimulators(udids: [String], verbose: Bool) throws {
        for udid in udids {
            Log.v("[Scheduler] Shutting down \(udid)")
            _ = try? ProcessUtils.runProcess("/usr/bin/xcrun", ["simctl", "shutdown", udid])
        }
    }

    static func deleteSimulators(udids: [String], verbose: Bool) throws {
        for udid in udids {
            Log.v("[Scheduler] Deleting \(udid)")
            _ = try? ProcessUtils.runProcess("/usr/bin/xcrun", ["simctl", "delete", udid])
        }
    }

    static func launchDetachedCleanup(udids: [String], cleanup: Bool, verbose: Bool) {
        guard !udids.isEmpty else { return }
        var parts: [String] = []
        for udid in udids {
            parts.append("/usr/bin/xcrun simctl shutdown '" + udid + "' || true")
            if cleanup {
                parts.append("/usr/bin/xcrun simctl delete '" + udid + "' || true")
            }
        }
        let body = parts.joined(separator: "; ")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        proc.arguments = ["/bin/bash", "-lc", body]

        // Detach stdio so it can outlive the parent without tying to terminals
        let devNullIn = FileHandle(forReadingAtPath: "/dev/null")
        let devNullOut = FileHandle(forWritingAtPath: "/dev/null")
        proc.standardInput = devNullIn
        proc.standardOutput = devNullOut
        proc.standardError = devNullOut

        do {
            try proc.run()
            Log.v("[Scheduler] Spawned detached cleanup for \(udids.count) simulator(s)")
        } catch {
            Log.v("[Scheduler] Failed to spawn detached cleanup: \(error)")
        }
    }
}
