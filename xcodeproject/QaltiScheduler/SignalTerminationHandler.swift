import Foundation
import Dispatch

final class SignalTerminationHandler {
    private var sources: [DispatchSourceSignal] = []
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { handler() }
            src.resume()
            sources.append(src)
        }
    }
}
