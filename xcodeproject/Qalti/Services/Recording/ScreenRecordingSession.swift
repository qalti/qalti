import Foundation
import AVFoundation
import CoreVideo
import CoreMedia
import IOSurface

final class ScreenRecordingSession: Loggable, @unchecked Sendable {

    private enum RecorderError: Swift.Error, LocalizedError {
        case surfaceUnavailable
        case writerInitializationFailed(String)
        case pixelBufferCreationFailed(OSStatus)
        case pixelBufferPoolUnavailable

        var errorDescription: String? {
            switch self {
            case .surfaceUnavailable:
                return "No IOSurface available for recording"
            case .writerInitializationFailed(let message):
                return "Failed to prepare writer: \(message)"
            case .pixelBufferCreationFailed(let status):
                return "Failed to create pixel buffer from pool (status: \(status))"
            case .pixelBufferPoolUnavailable:
                return "Pixel buffer pool is unavailable"
            }
        }
    }

    private let timebase: TestTimebase
    let outputURL: URL
    private let framesPerSecond: Int
    private let surfaceProvider: () -> IOSurface?
    private let fileManager: FileSystemManaging
    private let processingQueue = DispatchQueue(label: "com.aiqa.qalti.screenrecording.processing", qos: .userInitiated)

    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var writerStartTime: CMTime?
    private var frameTimer: DispatchSourceTimer?
    private var currentFormat: (width: Int, height: Int, pixelFormat: OSType, bytesPerRow: Int)?
    private var isRunning = false
    private var stopCompletion: (() -> Void)?

    init(
        timebase: TestTimebase,
        outputURL: URL,
        framesPerSecond: Int = 30,
        surfaceProvider: @escaping () -> IOSurface?,
        fileManager: FileSystemManaging = FileManager.default
    ) {
        self.timebase = timebase
        self.outputURL = outputURL
        self.framesPerSecond = framesPerSecond
        self.surfaceProvider = surfaceProvider
        self.fileManager = fileManager
    }

    func start() throws {
        guard !isRunning else {
            logger.debug("Recording already running, ignoring start request")
            return
        }

        guard surfaceProvider() != nil else {
            throw RecorderError.surfaceUnavailable
        }

        logger.info("Recording start requested: \(outputURL.lastPathComponent)")
        try prepareOutputFile()
        isRunning = true
        startFrameDriver()
    }

    func stop(completion: (() -> Void)? = nil) {
        logger.info("Recording stop requested")
        processingQueue.async { [weak self] in
            guard let self else { return }
            guard self.isRunning else {
                completion?()
                return
            }

            self.isRunning = false
            self.stopCompletion = completion
            stopFrameDriver()

            guard let writer = self.writer else {
                self.finishStop()
                return
            }

            switch writer.status {
            case .writing:
                self.writerInput?.markAsFinished()
                writer.finishWriting { [weak self] in
                    self?.finishStop()
                }
            case .unknown:
                writer.cancelWriting()
                self.finishStop()
            default:
                self.finishStop()
            }
        }
    }

    private func finishStop() {
        let performCleanup = { [weak self] in
            guard let self else { return }
            self.logger.info("Recording finished writing to disk")
            self.writer = nil
            self.writerInput = nil
            self.pixelBufferAdaptor = nil
            self.writerStartTime = nil
            self.currentFormat = nil

            let completion = self.stopCompletion
            self.stopCompletion = nil
            completion?()
        }

        if Thread.isMainThread {
            performCleanup()
        } else {
            DispatchQueue.main.async {
                performCleanup()
            }
        }
    }

    private func startFrameDriver() {
        guard frameTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: processingQueue)
        timer.schedule(deadline: .now(), repeating: .nanoseconds(1_000_000_000 / framesPerSecond), leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in
            self?.captureFrame()
        }
        timer.resume()
        frameTimer = timer
    }

    private func stopFrameDriver() {
        frameTimer?.cancel()
        frameTimer = nil
    }

    private func prepareOutputFile() throws {
        let directory = outputURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        if fileManager.fileExists(atPath: outputURL.path, isDirectory: nil) {
            try fileManager.removeItem(at: outputURL)
        }
    }

    private func captureFrame() {
        guard isRunning else { return }
        guard let surface = surfaceProvider() else {
            logger.debug("Skipping frame: IOSurface unavailable")
            return
        }

        do {
            try configureWriterIfNeeded(for: surface)
            guard let adaptor = pixelBufferAdaptor else { return }

            let hostTime = CMClockGetTime(CMClockGetHostTimeClock())
            let pts = timebase.videoTime(forHostTime: hostTime)

            try startWriterIfNeeded(at: pts)

            guard let pool = adaptor.pixelBufferPool else {
                logger.debug("Pixel buffer pool unavailable; dropping frame")
                return
            }

            var pixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
            guard status == kCVReturnSuccess, let pixelBuffer else {
                logger.error("Failed to create pixel buffer from pool: \(status)")
                return
            }

            guard copy(surface: surface, into: pixelBuffer) else {
                logger.error("Failed to copy IOSurface into pixel buffer")
                return
            }

            guard writerInput?.isReadyForMoreMediaData == true else {
                logger.debug("Writer input not ready; dropping frame")
                return
            }

            if adaptor.append(pixelBuffer, withPresentationTime: pts) == false {
                logger.error("Failed to append pixel buffer: \(writer?.error?.localizedDescription ?? "unknown error")")
            }
        } catch {
            logger.error("Recording pipeline error: \(error.localizedDescription)")
            stop()
        }
    }

    private func configureWriterIfNeeded(for surface: IOSurface) throws {
        let width = IOSurfaceGetWidth(surface)
        let height = IOSurfaceGetHeight(surface)
        let pixelFormat = IOSurfaceGetPixelFormat(surface)
        let bytesPerRow = IOSurfaceGetBytesPerRow(surface)

        if let currentFormat,
           currentFormat.width == width,
           currentFormat.height == height,
           currentFormat.pixelFormat == pixelFormat,
           currentFormat.bytesPerRow == bytesPerRow,
           writer != nil,
           writerInput != nil,
           pixelBufferAdaptor != nil {
            return
        }

        writer?.cancelWriting()
        writer = nil
        writerInput = nil
        pixelBufferAdaptor = nil
        writerStartTime = nil

        try prepareOutputFile()

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let targetBitrate = 1_000_000 // ~0.125 MB/s target to keep files small
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: targetBitrate,
                AVVideoExpectedSourceFrameRateKey: framesPerSecond,
                AVVideoAllowFrameReorderingKey: false
            ]
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true

        let sourceAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferBytesPerRowAlignmentKey as String: bytesPerRow
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: sourceAttributes)

        guard writer.canAdd(input) else {
            throw RecorderError.writerInitializationFailed("Writer rejected video input")
        }
        writer.add(input)

        self.writer = writer
        self.writerInput = input
        self.pixelBufferAdaptor = adaptor
        self.currentFormat = (width: width, height: height, pixelFormat: pixelFormat, bytesPerRow: bytesPerRow)
    }

    private func startWriterIfNeeded(at pts: CMTime) throws {
        guard let writer else {
            throw RecorderError.writerInitializationFailed("Writer instance missing")
        }

        if writer.status == .failed {
            throw RecorderError.writerInitializationFailed(writer.error?.localizedDescription ?? "Writer failed")
        }

        guard writerStartTime == nil else { return }

        writerStartTime = pts
        if writer.startWriting() {
            writer.startSession(atSourceTime: pts)
        } else {
            throw RecorderError.writerInitializationFailed(writer.error?.localizedDescription ?? "Failed to start writing")
        }
    }

    private func copy(surface: IOSurface, into pixelBuffer: CVPixelBuffer) -> Bool {
        IOSurfaceLock(surface, .readOnly, nil)
        CVPixelBufferLockBaseAddress(pixelBuffer, [])

        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            IOSurfaceUnlock(surface, .readOnly, nil)
        }

        let surfaceBase = IOSurfaceGetBaseAddress(surface)
        guard let pixelBase = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return false
        }

        let srcBytesPerRow = IOSurfaceGetBytesPerRow(surface)
        let dstBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard srcBytesPerRow == dstBytesPerRow else {
            logger.error("Bytes per row mismatch between IOSurface (\(srcBytesPerRow)) and pixel buffer (\(dstBytesPerRow))")
            return false
        }

        let copyBytes = srcBytesPerRow * IOSurfaceGetHeight(surface)
        memcpy(pixelBase, surfaceBase, copyBytes)

        return true
    }
}
