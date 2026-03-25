import Foundation
import Logging

protocol Loggable {}

extension Loggable {
    static var logger: Logger {
        let typeName = String(reflecting: Self.self)
        return LoggerStorage.logger(forTypeName: typeName)
    }
    var logger: Logger {
        type(of: self).logger
    }
}

private enum LoggerStorage {
    static let lock = NSLock()
    static var cache: [String: Logger] = [:]
    
    static func logger(forTypeName typeName: String) -> Logger {
        lock.lock(); defer { lock.unlock() }
        if let existing = cache[typeName] { return existing }
        let created = AppLogging.logger(typeName)
        cache[typeName] = created
        return created
    }
}


