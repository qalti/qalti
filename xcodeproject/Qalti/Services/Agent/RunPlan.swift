import Foundation

enum SuiteRunnerError: LocalizedError {
    case missingFolder(String)
    case noTests(String)
    case noRunnableTests(String)

    var errorDescription: String? {
        switch self {
        case .missingFolder(let path):
            return "Tests folder not found: \(path)"
        case .noTests(let folderName):
            return "No supported test files found inside \(folderName)."
        case .noRunnableTests(let folderName):
            return "No runnable tests found inside \(folderName)."
        }
    }
}

struct RunPlan {
    let tests: [URL]
    let suiteFolder: URL

    init(items: [URL], runsRoot: URL, fileManager: FileSystemManaging = FileManager.default) throws {
        let normalizedItems = items.map { $0.standardizedFileURL }

        if normalizedItems.count == 1 {
            let candidate = normalizedItems[0]
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
                let tests = try Self.discoverTests(in: candidate, fileManager: fileManager)
                guard !tests.isEmpty else {
                    throw SuiteRunnerError.noTests(candidate.lastPathComponent)
                }
                self.tests = tests
                self.suiteFolder = candidate
                return
            }
        }

        let collectedTests = Self.collectTests(from: normalizedItems, fileManager: fileManager)
        guard !collectedTests.isEmpty else {
            let name = normalizedItems.first?.lastPathComponent ?? "selection"
            throw SuiteRunnerError.noRunnableTests(name)
        }

        self.tests = collectedTests
        self.suiteFolder = Self.commonSuiteFolder(for: collectedTests, fallback: runsRoot)
    }

    var isSingleTest: Bool {
        tests.count == 1
    }

    var isSuiteRun: Bool {
        tests.count > 1
    }

    func runRoot(for runsRoot: URL, runIdentifier: String) -> URL {
        let base = runsRoot.standardizedFileURL
        if isSingleTest {
            return base
        }
        return base.appendingPathComponent(runIdentifier, isDirectory: true)
    }

    func testRunURL(for testFile: URL, preferredName: String?, runRoot: URL, runIdentifier: String) -> URL {
        let baseRoot = runRoot.standardizedFileURL

        if isSingleTest {
            return baseRoot.appendingPathComponent("\(runIdentifier).json", isDirectory: false)
        }

        let trimmedName = preferredName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = testFile.deletingPathExtension().lastPathComponent
        let baseName: String
        if let trimmedName, !trimmedName.isEmpty {
            baseName = trimmedName
        } else if !fallbackName.isEmpty {
            baseName = fallbackName
        } else {
            baseName = "test"
        }

        let filename = "\(baseName).json"
        return baseRoot.appendingPathComponent(filename, isDirectory: false)
    }

    private static func discoverTests(in folder: URL, fileManager: FileSystemManaging) throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SuiteRunnerError.missingFolder(folder.path)
        }

        var discovered: [URL] = []

        let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: nil
        )

        while let item = enumerator?.nextObject() as? URL {
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: item.path, isDirectory: &isDir), !isDir.boolValue,
               TestFileLoader.isSupportedExtension(item.pathExtension) {
                discovered.append(item.standardizedFileURL)
            }
        }

        return discovered.sorted { lhs, rhs in
            lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
        }
    }

    private static func collectTests(from items: [URL], fileManager: FileSystemManaging) -> [URL] {
        var collected: [URL] = []
        var seen: Set<URL> = []
        for item in items {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory) else {
                continue
            }

            if isDirectory.boolValue {
                if let tests = try? discoverTests(in: item, fileManager: fileManager) {
                    for test in tests {
                        if seen.insert(test).inserted {
                            collected.append(test)
                        }
                    }
                }
            } else if isSupportedTestFile(item) {
                if seen.insert(item).inserted {
                    collected.append(item)
                }
            }
        }

        return collected.sorted { lhs, rhs in
            lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
        }
    }

    private static func isSupportedTestFile(_ url: URL) -> Bool {
        TestFileLoader.isSupportedExtension(url.pathExtension)
    }

    private static func commonSuiteFolder(for tests: [URL], fallback: URL) -> URL {
        guard let firstParent = tests.first?.deletingLastPathComponent().standardizedFileURL else {
            return fallback
        }

        var commonPath = firstParent.path
        for test in tests.dropFirst() {
            let otherPath = test.deletingLastPathComponent().standardizedFileURL.path
            commonPath = commonDirectoryPrefix(commonPath, otherPath)
            if commonPath.isEmpty || commonPath == "/" {
                break
            }
        }

        if commonPath.isEmpty || commonPath == "/" {
            commonPath = firstParent.path
        }

        return URL(fileURLWithPath: commonPath, isDirectory: true)
    }

    private static func commonDirectoryPrefix(_ lhs: String, _ rhs: String) -> String {
        let lhsHasRoot = lhs.hasPrefix("/")
        let rhsHasRoot = rhs.hasPrefix("/")
        let lhsComponents = lhs.split(separator: "/", omittingEmptySubsequences: true)
        let rhsComponents = rhs.split(separator: "/", omittingEmptySubsequences: true)

        var result: [Substring] = []
        for (left, right) in zip(lhsComponents, rhsComponents) {
            if left == right {
                result.append(left)
            } else {
                break
            }
        }

        guard !result.isEmpty else {
            return lhsHasRoot && rhsHasRoot ? "/" : ""
        }

        let joined = result.joined(separator: "/")
        return (lhsHasRoot || rhsHasRoot) ? "/\(joined)" : joined
    }
}
