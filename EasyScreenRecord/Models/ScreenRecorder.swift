import Foundation
import ScreenCaptureKit
import AVFoundation
import Combine
import AppKit
import SwiftUI

class ScreenRecorder: NSObject, ObservableObject, SCStreamOutput {
    enum RecordingState {
        case idle
        case starting
        case recording
        case stopping
        case error(Error)
    }

    @Published var state: RecordingState = .idle
    @Published var availableContent: SCShareableContent?
    
    // UI Helpers
    var isRecording: Bool {
        if case .recording = state { return true }
        if case .stopping = state { return true }
        return false
    }
    
    var isBusy: Bool {
        if case .starting = state { return true }
        if case .stopping = state { return true }
        return false
    }
    
    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    // Zoom & Region settings
    private(set) var zoomScale: CGFloat = 2.0
    private(set) var baseRegion: CGRect? // nil means full screen
    
    // Zoom Logic Internals
    private var lastTargetPosition: CGPoint = .zero
    private var currentSourceRect: CGRect = .zero
    private var displaySize: CGSize = .zero
    private var currentSmoothScale: CGFloat = 1.0
    private var isTypingDetected = false
    
    // Timers & Windows
    private var timer: Timer?
    private var overlayWindow: NSWindow?
    private var dimmingWindow: NSWindow?
    private var dimmingViewModel: DimmingViewModel?
    private var lastUpdateTimestamp: Date = .distantPast

    // Serial queue for writing to ensure safety
    private let writingQueue = DispatchQueue(label: "com.nya3neko2.EasyScreenRecord.writingQueue", qos: .userInitiated)
    private var isWritingSessionStarted = false
    private var isStopping = false // Flag to prevent new writes during stop

    func setZoomScale(_ scale: CGFloat) {
        self.zoomScale = scale
        DispatchQueue.main.async {
            self.updateOverlaySize()
        }
    }

    func setBaseRegion(_ region: CGRect?) {
        self.baseRegion = region
    }

    @MainActor
    func startCapture() async {
        guard case .idle = state else { return }
        state = .starting
        
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            self.availableContent = content
            
            guard let display = content.displays.first else {
                throw NSError(domain: "ScreenRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: "No display found"])
            }
            
            displaySize = CGSize(width: CGFloat(display.width), height: CGFloat(display.height))
            
            let config = SCStreamConfiguration()
            config.width = Int(displaySize.width) * 2
            config.height = Int(displaySize.height) * 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            config.queueDepth = 8
            config.showsCursor = true
            
            let filter = SCContentFilter(display: display, excludingWindows: [])
            
            // Reset Session State
            isWritingSessionStarted = false
            isStopping = false

            // Reset Zoom State
            currentSmoothScale = 1.0
            isTypingDetected = false
            currentSourceRect = CGRect(origin: .zero, size: displaySize)

            // Initialize lastTargetPosition based on baseRegion or screen center
            if let region = baseRegion {
                // baseRegion is in NSWindow coordinates (bottom-left origin)
                // Convert center to top-left origin
                let centerX = region.midX
                let centerY = displaySize.height - region.midY
                lastTargetPosition = CGPoint(x: centerX, y: centerY)
            } else {
                lastTargetPosition = CGPoint(x: displaySize.width / 2, y: displaySize.height / 2)
            }

            // Setup Asset Writer
            try setupAssetWriter(width: config.width, height: config.height)
            
            // Setup Stream
            let newStream = SCStream(filter: filter, configuration: config, delegate: self)
            // Use local var to avoid self.stream race access in early init? No, safer to assign after addStreamOutput
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: writingQueue)
            self.stream = newStream
            
            try await newStream.startCapture()
            
            // Setup Windows
            setupOverlayWindow() // Zoom indicator
            setupDimmingWindow() // Grey out background

            // Initialize dimming hole rect based on baseRegion or full screen
            if let viewModel = dimmingViewModel, let screen = NSScreen.main {
                let screenHeight = screen.frame.height
                if let region = baseRegion {
                    // baseRegion is in NSWindow coordinates (bottom-left origin)
                    // Convert to top-left origin for SwiftUI
                    let holeY = screenHeight - region.origin.y - region.height
                    viewModel.holeRect = CGRect(x: region.origin.x, y: holeY, width: region.width, height: region.height)
                } else {
                    // Full screen - no dimming
                    viewModel.holeRect = CGRect(origin: .zero, size: screen.frame.size)
                }
            }

            self.overlayWindow?.orderFrontRegardless()
            self.dimmingWindow?.orderFrontRegardless()

            startZoomTimer()
            
            withAnimation {
                state = .recording
            }
            print("Recording started.")
            
        } catch {
            print("Failed to start capture: \(error)")
            state = .error(error)
            cleanupWindows()
            stopZoomTimer()
            
            // Allow user to see error briefly or just reset
            try? await Task.sleep(nanoseconds: 1 * 1_000_000_000)
            state = .idle
        }
    }
    
    @MainActor
    func stopCapture() async {
        guard case .recording = state else { return }

        // Change state immediately to block new start requests
        state = .stopping
        stopZoomTimer()
        cleanupWindows() // Hide windows immediately for better UX

        let activeStream = self.stream
        self.stream = nil // Detach stream reference

        // Capture references before queue operation
        let writer = self.assetWriter
        let input = self.videoInput
        let outputURL = writer?.outputURL

        do {
            if let s = activeStream {
                try await s.stopCapture()
            }

            // Close writer on queue
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                writingQueue.async { [weak self] in
                    defer {
                        continuation.resume()
                    }

                    // Set stopping flag first
                    self?.isStopping = true

                    guard let writer = writer else { return }

                    if writer.status == .writing {
                        input?.markAsFinished()
                        let semaphore = DispatchSemaphore(value: 0)
                        writer.finishWriting {
                            semaphore.signal()
                        }
                        _ = semaphore.wait(timeout: .now() + 5.0)
                    } else if writer.status != .completed {
                        // If we never started writing or errored, cancel
                        writer.cancelWriting()
                    }
                }
            }

            // Cleanup references on main thread
            self.assetWriter = nil
            self.videoInput = nil
            self.pixelBufferAdaptor = nil
            self.isWritingSessionStarted = false
            self.isStopping = false

            withAnimation {
                state = .idle
            }

            if let url = outputURL {
                print("Recording finished: \(url.path)")
            }

        } catch {
            print("Failed to stop capture: \(error)")
            // Cleanup on error too
            self.assetWriter = nil
            self.videoInput = nil
            self.pixelBufferAdaptor = nil
            self.isWritingSessionStarted = false
            self.isStopping = false
            state = .error(error)
        }
    }
    
    // MARK: - Internal
    
    private func setupAssetWriter(width: Int, height: Int) throws {
        let evenWidth = (width >> 1) << 1
        let evenHeight = (height >> 1) << 1

        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("Record-\(UUID().uuidString).mov")

        let writer = try AVAssetWriter(outputURL: fileURL, fileType: .mov)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: evenWidth,
            AVVideoHeightKey: evenHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: evenWidth * evenHeight * 4,
                AVVideoExpectedSourceFrameRateKey: 60,
                AVVideoMaxKeyFrameIntervalKey: 60
            ]
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true

        // Create pixel buffer adaptor for handling CVPixelBuffer from ScreenCaptureKit
        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: evenWidth,
            kCVPixelBufferHeightKey as String: evenHeight
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )

        if writer.canAdd(input) {
            writer.add(input)
        } else {
            throw NSError(domain: "app", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cant add input"])
        }

        // Start writing immediately to transition state to 'writing'
        // Session will be started when first frame arrives
        if !writer.startWriting() {
            throw writer.error ?? NSError(domain: "app", code: -1, userInfo: [NSLocalizedDescriptionKey: "Start writing failed"])
        }

        self.assetWriter = writer
        self.videoInput = input
        self.pixelBufferAdaptor = adaptor
    }
    
    private func setupOverlayWindow() {
        // Red frame window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false // Prevent double-free crash

        let contentView = NSHostingView(rootView: RecordingOverlayView(scale: zoomScale))
        window.contentView = contentView
        self.overlayWindow = window
    }
    
    private func setupDimmingWindow() {
        guard let screen = NSScreen.main else { return }

        // Create a full screen window with a dynamic 'hole'
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.isReleasedWhenClosed = false // Prevent double-free crash

        // Create view model for dynamic updates
        let viewModel = DimmingViewModel()
        self.dimmingViewModel = viewModel

        // Initialize hole rect to full screen (no dimming initially)
        viewModel.holeRect = CGRect(origin: .zero, size: screen.frame.size)

        let contentView = NSHostingView(rootView: DimmingView(viewModel: viewModel))
        window.contentView = contentView
        self.dimmingWindow = window
    }
    
    private func cleanupWindows() {
        overlayWindow?.close()
        overlayWindow = nil
        dimmingWindow?.close()
        dimmingWindow = nil
        dimmingViewModel = nil
    }
    
    private func updateOverlaySize() {
        guard let window = overlayWindow else { return }
        let zoomWidth = displaySize.width / zoomScale
        let zoomHeight = displaySize.height / zoomScale
        window.setContentSize(NSSize(width: zoomWidth, height: zoomHeight))
    }
    
    // MARK: - Zoom Logic
    
    private func startZoomTimer() {
        // Ensure timer runs on main thread for UI updates
        DispatchQueue.main.async { [weak self] in
            self?.timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
                self?.updateZoom()
            }
            // Add to common run loop mode to ensure it runs during tracking
            if let timer = self?.timer {
                RunLoop.main.add(timer, forMode: .common)
            }
        }
    }
    
    private func stopZoomTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private var lastLogTime: Date = .distantPast

    private func updateZoom() {
        let typingPosition = AccessibilityUtils.getTypingCursorPosition()

        let targetScale: CGFloat
        var targetX: CGFloat
        var targetY: CGFloat

        // Debug log (throttled to once per second)
        #if DEBUG
        if Date().timeIntervalSince(lastLogTime) > 1.0 {
            if let pos = typingPosition {
                print("[Zoom] Typing detected at: \(pos), scale: \(currentSmoothScale)")
            } else {
                print("[Zoom] No typing detected, scale: \(currentSmoothScale)")
            }
            lastLogTime = Date()
        }
        #endif

        // Calculate default center position (in top-left origin coordinates)
        let defaultCenterX: CGFloat
        let defaultCenterY: CGFloat
        if let region = baseRegion {
            // baseRegion is in NSWindow coordinates (bottom-left origin)
            // Convert to top-left origin
            defaultCenterX = region.midX
            defaultCenterY = displaySize.height - region.midY
        } else {
            defaultCenterX = displaySize.width / 2
            defaultCenterY = displaySize.height / 2
        }

        if let typingPos = typingPosition {
            // Accessibility coordinates are screen coordinates (top-left origin)
            // Check if typing position is within baseRegion (need to convert baseRegion to top-left)
            let isInRegion: Bool
            if let region = baseRegion {
                let regionTopLeft = CGRect(
                    x: region.origin.x,
                    y: displaySize.height - region.origin.y - region.height,
                    width: region.width,
                    height: region.height
                )
                isInRegion = regionTopLeft.contains(typingPos)
            } else {
                isInRegion = true
            }

            if isInRegion {
                targetScale = zoomScale
                targetX = typingPos.x
                targetY = typingPos.y
                isTypingDetected = true
            } else {
                targetScale = 1.0
                targetX = defaultCenterX
                targetY = defaultCenterY
                isTypingDetected = false
            }
        } else {
            targetScale = 1.0
            targetX = defaultCenterX
            targetY = defaultCenterY
            isTypingDetected = false
        }

        // Smooth interpolation
        let scaleSmoothing: CGFloat = 0.08
        let posSmoothing: CGFloat = 0.12

        currentSmoothScale += (targetScale - currentSmoothScale) * scaleSmoothing
        lastTargetPosition.x += (targetX - lastTargetPosition.x) * posSmoothing
        lastTargetPosition.y += (targetY - lastTargetPosition.y) * posSmoothing

        // Calculate zoom area size based on baseRegion if set, otherwise full screen
        let baseWidth: CGFloat
        let baseHeight: CGFloat
        if let region = baseRegion {
            baseWidth = region.width
            baseHeight = region.height
        } else {
            baseWidth = displaySize.width
            baseHeight = displaySize.height
        }

        let activeZoomWidth = baseWidth / currentSmoothScale
        let activeZoomHeight = baseHeight / currentSmoothScale

        // Calculate source rect origin (top-left corner of the zoom area)
        var sourceX = lastTargetPosition.x - activeZoomWidth / 2
        var sourceY = lastTargetPosition.y - activeZoomHeight / 2

        // Clamp to screen bounds
        sourceX = max(0, min(sourceX, displaySize.width - activeZoomWidth))
        sourceY = max(0, min(sourceY, displaySize.height - activeZoomHeight))

        // SCStreamConfiguration.sourceRect uses top-left origin (same as Accessibility)
        let newSourceRect = CGRect(x: sourceX, y: sourceY, width: activeZoomWidth, height: activeZoomHeight)
        currentSourceRect = newSourceRect

        // Update Overlay Window and Dimming
        // NSWindow frame uses bottom-left origin, so we need to convert Y
        if let screen = NSScreen.main {
            let screenHeight = screen.frame.height
            // Convert from top-left to bottom-left origin for window positioning
            let windowY = screenHeight - sourceY - activeZoomHeight

            // Update overlay window
            if let window = self.overlayWindow {
                window.setFrame(NSRect(x: sourceX, y: windowY, width: activeZoomWidth, height: activeZoomHeight), display: true)
                window.alphaValue = self.isTypingDetected ? 1.0 : 0.0
            }

            // Update dimming hole rect (SwiftUI uses top-left origin within the window)
            // The dimming window covers the full screen, so we use sourceX/sourceY directly
            if let viewModel = self.dimmingViewModel {
                viewModel.holeRect = CGRect(x: sourceX, y: sourceY, width: activeZoomWidth, height: activeZoomHeight)
            }
        }

        // Stream Update (throttled to avoid too many config updates)
        if Date().timeIntervalSince(lastUpdateTimestamp) > 0.033 { // ~30fps for config updates
            if let stream = stream {
                let config = SCStreamConfiguration()
                config.sourceRect = currentSourceRect
                config.width = Int(displaySize.width) * 2
                config.height = Int(displaySize.height) * 2
                config.showsCursor = true
                stream.updateConfiguration(config) { error in
                    if let error = error {
                        print("Failed to update stream configuration: \(error.localizedDescription)")
                    }
                }
            }
            lastUpdateTimestamp = Date()
        }
    }

    // MARK: - Output
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }

        // Pass to writing queue
        writingQueue.async { [weak self] in
            guard let self = self else { return }

            // 1. Check stopping flag first
            if self.isStopping { return }

            // 2. Check writer state
            guard let writer = self.assetWriter,
                  let input = self.videoInput,
                  let adaptor = self.pixelBufferAdaptor else { return }

            if writer.status == .failed {
                if let error = writer.error as NSError? {
                    print("Writer failed: \(error.localizedDescription), code: \(error.code), domain: \(error.domain)")
                } else {
                    print("Writer failed: unknown error")
                }
                return
            }

            if writer.status == .completed || writer.status == .cancelled {
                return
            }

            // 3. Validate Buffer and get pixel buffer
            guard CMSampleBufferDataIsReady(sampleBuffer), CMSampleBufferIsValid(sampleBuffer) else { return }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

            // 4. Start Session if needed (startWriting already called in setupAssetWriter)
            if !self.isWritingSessionStarted && writer.status == .writing {
                writer.startSession(atSourceTime: presentationTime)
                self.isWritingSessionStarted = true
                print("AVAssetWriter session started at \(presentationTime.seconds)")
            }

            // 5. Append using pixel buffer adaptor
            if self.isWritingSessionStarted && input.isReadyForMoreMediaData {
                if !adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                    if let error = writer.error as NSError? {
                        print("Failed to append buffer: \(error.localizedDescription), code: \(error.code)")
                    }
                }
            }
        }
    }
}

extension ScreenRecorder: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("Stream stop error: \(error)")
    }
}

// MARK: - Dimming View Model
class DimmingViewModel: ObservableObject {
    @Published var holeRect: CGRect = .zero
}

// MARK: - Dimming View
struct DimmingView: View {
    @ObservedObject var viewModel: DimmingViewModel

    var body: some View {
        Canvas { context, size in
            // Draw semi-transparent black over everything
            let fullRect = CGRect(origin: .zero, size: size)

            // Create a path with a hole
            var path = Path(fullRect)
            path.addRect(viewModel.holeRect)

            context.fill(path, with: .color(.black.opacity(0.3)), style: FillStyle(eoFill: true))
        }
        .edgesIgnoringSafeArea(.all)
    }
}
