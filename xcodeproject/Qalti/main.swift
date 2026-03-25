import Foundation
import SwiftUI

let args = CommandLine.arguments
if args.count >= 2 && args[1] == "cli" {
    Task {
        let errorCapturer = ErrorCapturerService()
        let idb = IdbManager(errorCapturer: errorCapturer)

        let exitCode = await CLICommand.run(
            dateProvider: SystemDateProvider(),
            idbManager: idb,
            errorCapturer: errorCapturer
        )
        exit(exitCode.rawValue)
    }
    RunLoop.main.run()
} else {
    QaltiApp.main()
}
