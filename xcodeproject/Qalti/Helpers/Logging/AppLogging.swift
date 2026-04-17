import Foundation
import Logging
import Puppy

final class AppLogging {
    private(set) static var isBootstrapped: Bool = false
    private static let bootstrapLock = NSLock()
    private static var puppyRef: Puppy?
    private static var logsDirectoryRef: URL?
    
    /// Initialize swift-log with Puppy backends.
    /// - Parameters:
    ///   - stderrLevel: log level for stderr transport
    ///   - fileLevel: log level for file transport
    ///   - logsDir: custom logs directory; defaults to ~/Library/Logs/Qalti on macOS
    ///   - logFileName: custom log file name; defaults to "qalti.log"
    ///   - maxFileSize: rotation max file size in bytes (default: 20MB)
    ///   - maxArchivedFilesCount: max number of archived files (default: 10)
    /// 
    /// Logging formats:
    /// - File (full): "[yyyy-MM-dd'T'HH:mm:ss.SSSZ] [LVL] [LoggerName] message"
    /// - Stderr (timeOnly): "[HH:mm:ss.S-LVL-LoggerName] message"
    /// Notes:
    /// - Each transport gates by its own level; handler.logLevel set to .trace for permissive pass-through.
    /// - In SwiftUI Preview contexts, prefer print() over logging.
    /// Usage: Create private class-level logger: `private let logger = AppLogging.logger("ClassName")`
    static func bootstrap(
        stderrLevel: Logger.Level = .info,
        fileLevel: Logger.Level = .debug,
        logsDir: URL? = nil,
        logFileName: String? = nil,
        maxFileSize: Int = 20 * 1024 * 1024,
        maxArchivedFilesCount: Int = 10
    ) {
        bootstrapLock.lock(); defer { bootstrapLock.unlock() }
        guard !isBootstrapped else { return }

        let fullFormatter = AppLogFormatter(timestampStyle: .full)
        let stderrFormatter = AppLogFormatter(timestampStyle: .timeOnly)

        let resolvedLogsDir: URL = logsDir ?? Self.logsDirectory
        logsDirectoryRef = resolvedLogsDir

        try? FileManager.default.createDirectory(at: resolvedLogsDir, withIntermediateDirectories: true)
        let fileName = (logFileName?.isEmpty == false) ? logFileName! : "qalti.log"
        let fileURL = resolvedLogsDir.appendingPathComponent(fileName)

        let stderrLogger = StderrLogger("com.qalti.stderr", logLevel: stderrLevel, logFormat: stderrFormatter)

        let rotationConfig = RotationConfig(
            suffixExtension: .date_uuid,
            maxFileSize: RotationConfig.ByteCount(maxFileSize),
            maxArchivedFilesCount: UInt8(clamping: maxArchivedFilesCount)
        )
        let fileRotation = try? FileRotationLogger(
            "com.qalti.file",
            logLevel: fileLevel.toPuppyLevel,
            logFormat: fullFormatter,
            fileURL: fileURL,
            rotationConfig: rotationConfig
        )
        if fileRotation == nil {
            fputs("QaltiLogging: file logger disabled (init failed)\n", stderr)
        }

        var transports: [Loggerable] = [stderrLogger]
        if let fileRotation { transports.append(fileRotation) }
        let puppy = Puppy(loggers: transports)
        puppyRef = puppy

        LoggingSystem.bootstrap { label in
            var handler = PuppyLogHandler(label: label, puppy: puppy)
            // Do not filter at handler; let individual transports filter
            handler.logLevel = .trace
            return handler
        }

        isBootstrapped = true
    }

    /// Convenience creator for a namespaced logger.
    static func logger(_ name: String) -> Logger {
        Logger(label: "com.qalti.\(name)")
    }

    static var logsDirectory: URL {
        if let dir = logsDirectoryRef { return dir }
        let base = FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("Library/Logs/Qalti", isDirectory: true)
    }
}

// MARK: - Formatter

struct AppLogFormatter: LogFormattable {
    enum TimestampStyle { case full, timeOnly }
    private let timestampStyle: TimestampStyle

    init(timestampStyle: TimestampStyle = .full) {
        self.timestampStyle = timestampStyle
    }
    /// Timestamp formatter.
    /// Why DateFormatter (not ISO8601DateFormatter):
    /// - DateFormatter is thread-safe on modern Apple OSes and can be shared safely if not mutated.
    /// - ISO8601DateFormatter is not Sendable and not guaranteed thread-safe for shared use.
    /// - We need a custom pattern: 1 fractional digit and numeric TZ without colon (e.g. +0200).
    /// Do not mutate this formatter after initialization.
    private static let tsFull: DateFormatter = {
        let f = DateFormatter()
        // Example: 2025-11-11T16:23:37.123+0200 (millisecond precision)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()
    private static let tsTimeOnly: DateFormatter = {
        let f = DateFormatter()
        // Example: 16:23:37.1
        f.dateFormat = "HH:mm:ss.S"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    func formatMessage(
        _ level: LogLevel,
        message: String,
        tag: String,
        function: String,
        file: String,
        line: UInt,
        swiftLogInfo: [String : String],
        label: String,
        date: Date,
        threadID: UInt64
    ) -> String {
        let ts: String = {
            switch timestampStyle {
            case .full: return AppLogFormatter.tsFull.string(from: date)
            case .timeOnly: return AppLogFormatter.tsTimeOnly.string(from: date)
            }
        }()
        let shortLevel = shortCode(forSwiftLogInfo: swiftLogInfo) ?? shortCode(for: level)
        // Prefer the Swift logger label (from swift-log) over the transport label.
        // Fallback to `tag`, then to transport `label` if nothing else is available.
        let swiftLoggerLabel = swiftLogInfo["label"] ?? tag
        let loggerName = prettyLabel(swiftLoggerLabel.isEmpty ? label : swiftLoggerLabel)
        switch timestampStyle {
        case .timeOnly:
            return "[\(ts)-\(shortLevel)-\(loggerName)] \(message)"
        case .full:
            return "[\(ts)] [\(shortLevel)] [\(loggerName)] \(message)"
        }
    }

    private func prettyLabel(_ label: String) -> String {
        if let last = label.split(separator: ".").last { return String(last) }
        return label
    }

    private func shortCode(forSwiftLogInfo info: [String:String]) -> String? {
        if let lv = info["level"]?.lowercased() {
            switch lv {
            case "trace": return "TRC"
            case "debug": return "DBG"
            case "info": return "INF"
            case "notice": return "NOT"
            case "warning": return "WRN"
            case "error": return "ERR"
            case "critical": return "CRT"
            default: return nil
            }
        }
        return nil
    }

    private func shortCode(for level: LogLevel) -> String {
        switch level {
        case .trace: return "TRC"
        case .debug: return "DBG"
        case .info: return "INF"
        case .warning: return "WRN"
        case .error: return "ERR"
        case .critical: return "CRT"
        case .verbose: return "VRB"
        case .notice: return "NTC"
        }
    }
}

// MARK: - Stderr logger

struct StderrLogger: Loggerable {
    let label: String
    let queue: DispatchQueue
    let logLevel: LogLevel
    let logFormat: LogFormattable?

    init(_ label: String, logLevel: Logger.Level = .info, logFormat: LogFormattable? = nil) {
        self.label = label
        self.queue = DispatchQueue(label: label)
        self.logLevel = logLevel.toPuppyLevel
        self.logFormat = logFormat
    }

    func log(_ level: LogLevel, string: String) {
        // Write synchronously to stderr to preserve ordering
        if let data = (string + "\n").data(using: .utf8) {
            FileHandle.standardError.write(data)
        } else {
            fputs(string + "\n", stderr)
            fflush(stderr)
        }
    }
}

// MARK: - Helpers

private extension Logger.Level {
    var toPuppyLevel: LogLevel {
        switch self {
        case .trace: return .trace
        case .debug: return .debug
        case .info: return .info
        case .notice: return .info
        case .warning: return .warning
        case .error: return .error
        case .critical: return .critical
        }
    }
}
