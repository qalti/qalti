import Foundation

struct TestSuiteRunContext {
    let plan: RunPlan
    let tests: [URL]
    let suiteFolder: URL
    let testsRoot: URL?
    let runRoot: URL
    let runIdentifier: String
    let suiteDisplayName: String
    let suiteRelativeComponents: [String]
    let startedAt: Date

    init(plan: RunPlan, runsRoot: URL, testsRoot: URL?, startedAt: Date = Date()) {
        let standardizedTests = plan.tests.map { $0.standardizedFileURL }
        let standardizedSuite = plan.suiteFolder.standardizedFileURL

        self.plan = plan
        tests = standardizedTests
        suiteFolder = standardizedSuite
        self.testsRoot = testsRoot?.standardizedFileURL
        self.startedAt = startedAt

        let relativeComponents = TestSuiteRunContext.deriveRelativeComponents(
            for: standardizedSuite,
            testsRoot: self.testsRoot
        )
        self.suiteRelativeComponents = relativeComponents.isEmpty
            ? [standardizedSuite.lastPathComponent]
            : relativeComponents

        if let displayName = suiteRelativeComponents.nonEmptyJoined(by: "/") {
            self.suiteDisplayName = displayName
        } else {
            self.suiteDisplayName = standardizedSuite.lastPathComponent
        }

        let runFolderName = "test_run_\(Self.runFolderFormatter.string(from: startedAt))"
        self.runIdentifier = runFolderName
        self.runRoot = plan.runRoot(for: runsRoot, runIdentifier: runFolderName)
    }

    func testRunURL(for testFile: URL, preferredName: String?) -> URL {
        plan.testRunURL(for: testFile, preferredName: preferredName, runRoot: runRoot, runIdentifier: runIdentifier)
    }

    func relativePath(for testFile: URL) -> String {
        let components = relativeComponents(for: testFile)
        return components.nonEmptyJoined(by: "/") ?? testFile.lastPathComponent
    }

    func relativeTestRunPath(for testRunURL: URL) -> String {
        let testRunPath = testRunURL.standardizedFileURL.path
        let runPath = runRoot.standardizedFileURL.path
        guard testRunPath.hasPrefix(runPath) else {
            return testRunURL.lastPathComponent
        }
        let suffix = String(testRunPath.dropFirst(runPath.count))
        return suffix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    // MARK: - Helpers

    private func relativeComponents(for testFile: URL) -> [String] {
        let testPath = testFile.standardizedFileURL.path
        let suitePath = suiteFolder.standardizedFileURL.path
        guard testPath.hasPrefix(suitePath) else {
            return [testFile.lastPathComponent]
        }

        let relative = String(testPath.dropFirst(suitePath.count))
        let trimmed = relative.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else {
            return [testFile.lastPathComponent]
        }

        return trimmed
            .split(separator: "/")
            .map { String($0) }
    }

    private static func deriveRelativeComponents(for suite: URL, testsRoot: URL?) -> [String] {
        guard let testsRoot else { return [] }
        let suitePath = suite.standardizedFileURL.path
        let testsPath = testsRoot.standardizedFileURL.path
        guard suitePath.hasPrefix(testsPath) else { return [] }
        let relative = String(suitePath.dropFirst(testsPath.count))
        let trimmed = relative.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return [] }
        return trimmed.split(separator: "/").map { String($0) }
    }

    private static let runFolderFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yy_MM_dd_HHmmss"
        return formatter
    }()
}

private extension Collection where Element == String {
    func nonEmptyJoined(by separator: String) -> String? {
        guard isEmpty == false else { return nil }
        return joined(separator: separator)
    }
}
