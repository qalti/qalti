import Foundation

enum RunIndicatorState: Equatable {
    case queued
    case running
    case success
    case failed
    case cancelled
}

struct RunIndicatorStatus: Equatable {
    let state: RunIndicatorState
}
