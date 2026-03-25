import Foundation
import ArgumentParser 

final class TestController {
    private var pending: [URL]
    private var results: [URL: Int32] = [:]
    private let lock = NSLock()

    init(tests: [URL]) {
        self.pending = tests
    }

    func nextTest(for worker: String) -> URL? {
        lock.lock(); defer { lock.unlock() }
        guard !pending.isEmpty else { return nil }
        return pending.removeFirst()
    }

    func reportResult(for test: URL, code: Int32) {
        lock.lock(); defer { lock.unlock() }
        results[test] = code
    }

    func resultsSnapshot() -> [URL: Int32] {
        lock.lock(); defer { lock.unlock() }
        return results
    }

    // MARK: - Static helpers used by CLI argument processing
    static func enumerateTests(in dir: URL) throws -> [URL] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
            throw ValidationError("Tests directory does not exist: \(dir.path)")
        }

        let allowedExts = ["test"]
        let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])

        var found: [URL] = []
        while let item = enumerator?.nextObject() as? URL {
            let ext = item.pathExtension.lowercased()
            if allowedExts.contains(ext) { found.append(item) }
        }

        return found.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
    }
}
