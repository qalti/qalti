import Foundation

enum Log {
    private static var _isVerbose: Bool = false

    static func setVerbose(_ enabled: Bool) {
        _isVerbose = enabled
    }

    static func v(_ message: @autoclosure () -> String) {
        if _isVerbose { print(message()) }
    }

    static func i(_ message: @autoclosure () -> String) {
        print(message())
    }

    static func e(_ message: @autoclosure () -> String) {
        fputs(message() + "\n", stderr)
        fflush(stderr)
    }
}


