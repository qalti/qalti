import Foundation
import CoreMedia

struct TestTimebase {
    let runStartDate: Date
    let videoStartHostTime: CMTime
    let preferredTimescale: CMTimeScale

    init(
        runStartDate: Date = Date(),
        videoStartHostTime: CMTime = CMClockGetTime(CMClockGetHostTimeClock()),
        preferredTimescale: CMTimeScale = 600
    ) {
        self.runStartDate = runStartDate
        self.videoStartHostTime = videoStartHostTime
        self.preferredTimescale = preferredTimescale
    }

    func videoTime(forHostTime hostTime: CMTime) -> CMTime {
        CMTimeSubtract(hostTime, videoStartHostTime)
    }

    func videoTime(for date: Date) -> CMTime {
        let delta = date.timeIntervalSince(runStartDate)
        return CMTime(seconds: delta, preferredTimescale: preferredTimescale)
    }
}

struct CapturedFrame {
    let pixelBuffer: CVPixelBuffer
    let captureHostTime: CMTime
}

protocol ScreenFrameSource: AnyObject {
    func start(handler: @escaping (CapturedFrame) -> Void) throws
    func stop()
}
