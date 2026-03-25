import Foundation

struct TestFileLoader {
    private let fileManager: FileSystemManaging
    private let contentParser: ContentParser

    /// Supported file extensions for test content (case-insensitive).
    static let supportedExtensions: Set<String> = ["json", "test", "txt"]

    /// Shared validation message for empty/invalid test content.
    static let emptyTestMessage = "Test has no actions"

    /// Determines whether a file extension is supported.
    static func isSupportedExtension(_ ext: String) -> Bool {
        supportedExtensions.contains(ext.lowercased())
    }

    /// Returns true when the test content contains any non-whitespace characters.
    static func hasRunnableContent(_ test: String) -> Bool {
        test.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    enum LoaderError: LocalizedError {
        case unsupportedExtension(String)
        case invalidJSONFormat(url: URL, underlyingError: Error)
        case unsupportedFormat

        var errorDescription: String? {
            switch self {
            case .unsupportedExtension(let ext):
                return "Unsupported test file extension: \(ext)"
            case .invalidJSONFormat(let url, let underlyingError):
                var details = ""
                if let decodingError = underlyingError as? DecodingError {
                    switch decodingError {
                    case .keyNotFound(let key, let context):
                        details = "Required key '\(key.stringValue)' was not found. Full path: \(context.codingPath.map(\.stringValue).joined(separator: "."))"
                    case .valueNotFound(let type, let context):
                        details = "A value of type '\(type)' was expected but not found. Full path: \(context.codingPath.map(\.stringValue).joined(separator: "."))"
                    case .typeMismatch(let type, let context):
                        details = "A value of type '\(type)' was expected but a different type was found. Full path: \(context.codingPath.map(\.stringValue).joined(separator: "."))"
                    case .dataCorrupted(let context):
                        details = "The data is corrupted. \(context.debugDescription)"
                    @unknown default:
                        details = "An unknown decoding error occurred."
                    }
                } else {
                    details = underlyingError.localizedDescription
                }
                return "The file '\(url.lastPathComponent)' is not a valid test run. Please check the JSON format. \(details)"
            case .unsupportedFormat:
                return "Unsupported test file format"
            }
        }
    }

    struct LoadResult {
        enum Source {
            case jsonActions
            case jsonRun
            case plainText
        }

        let test: String
        let source: Source
        let testRun: TestRunData?
        let totalLineCount: Int?
    }

    init(errorCapturer: ErrorCapturing, fileManager: FileSystemManaging = FileManager.default) {
        self.contentParser = ContentParser(errorCapturer: errorCapturer)
        self.fileManager = fileManager
    }

    func load(from url: URL) throws -> LoadResult {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "json":
            return try loadJSON(url: url)
        case "test", "txt":
            return try loadPlainText(url: url)
        default:
            throw LoaderError.unsupportedExtension(ext)
        }
    }

    // MARK: - Private helpers

    private func loadJSON(url: URL) throws -> LoadResult {
        do {
            guard let data = fileManager.contents(atPath: url.path) else {
                throw NSError(domain: "TestFileLoader", code: 1, userInfo: [NSLocalizedDescriptionKey: "File not found or couldn't be read."])
            }
            let decoder = JSONDecoder.withPreciseDateDecoding()

            let versionedTestRun = try decoder.decode(VersionedTestRun.self, from: data)
            let testRun = versionedTestRun.migrated(using: contentParser)

            return LoadResult(test: testRun.test, source: .jsonRun, testRun: testRun, totalLineCount: nil)

        } catch {
            throw LoaderError.invalidJSONFormat(url: url, underlyingError: error)
        }
    }

    private func loadPlainText(url: URL) throws -> LoadResult {
        guard let data = fileManager.contents(atPath: url.path) else {
            throw NSError(domain: "TestFileLoader", code: 1, userInfo: [NSLocalizedDescriptionKey: "File not found or couldn't be read."])
        }
        let content = String(data: data, encoding: .utf8) ?? ""

        return LoadResult(test: content, source: .plainText, testRun: nil, totalLineCount: content.count(where: { $0 == "\n" }))
    }
}
