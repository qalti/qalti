import Foundation
import IOSurface

/// Thread-safe store for the latest IOSurface coming from the target view.
/// Recording sessions can query this to fetch the most recent frame source without
/// coupling to the view model directly.
final class TargetSurfaceRegistry {
    static let shared = TargetSurfaceRegistry()

    private let lock = NSLock()
    private var surface: IOSurface?

    func update(surface: IOSurface?) {
        lock.lock()
        self.surface = surface
        lock.unlock()
    }

    func currentSurface() -> IOSurface? {
        lock.lock()
        let current = surface
        lock.unlock()
        return current
    }
}
