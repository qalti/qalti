import Foundation
import Logging

final class ErrorCapturerService: ObservableObject, Loggable, ErrorCapturing {
    func capture(error: Error) {
        logger.error("Captured error: \(error.localizedDescription)")
    }
}
