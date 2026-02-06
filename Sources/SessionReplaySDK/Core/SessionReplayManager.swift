//
//  SessionReplayManager.swift
//  SessionReplaySDK
//
//  Main orchestrator for session replay capture.
//  Coordinates video capture, logging, and network interception.
//
//  Created by AlmoutasemNabil on 2026.
//  Copyright © 2026 AlmoutasemNabil. All rights reserved.
//
//  This source code is licensed under the MIT license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Combine

#if canImport(UIKit)
import UIKit
import AVFoundation

public final class SessionReplayManager {

    // MARK: - Singleton

    public static let shared = SessionReplayManager()

    // MARK: - Public Properties

    public private(set) var config = SessionReplayConfig()
    public private(set) var logConfig = SessionLoggerConfig()
    public private(set) var isRecording = false
    public private(set) var currentSession: ReplaySession?

    /// Delegate for upload events
    public weak var uploadDelegate: SessionUploadDelegate?

    // MARK: - Private Properties

    private var displayLink: CADisplayLink?
    private var lastCaptureTime: CFTimeInterval = 0
    private var frameBuffer: [UIImage] = []
    private var videoWriter: VideoWriter?
    private var screenTransitions: [ScreenTransition] = []
    private var currentScreenName: String?

    private let captureQueue = DispatchQueue(label: "com.sessionreplay.capture", qos: .utility)
    private let processingQueue = DispatchQueue(label: "com.sessionreplay.processing", qos: .background)

    private var cancellables = Set<AnyCancellable>()
    private var viewTreeHash: Int = 0

    // MARK: - Initialization

    private init() {
        setupNotifications()
        setupSwizzling()
    }

    // MARK: - Configuration

    /// Configure video capture settings
    public func configure(_ config: SessionReplayConfig) {
        self.config = config
        ensureStorageDirectory()
    }

    /// Configure both video and logging settings
    public func configure(_ videoConfig: SessionReplayConfig, logConfig: SessionLoggerConfig) {
        self.config = videoConfig
        self.logConfig = logConfig
        ensureStorageDirectory()
        SessionLogger.shared.configure(logConfig)
    }

    // MARK: - Session Lifecycle

    /// Start a new recording session
    public func startSession() {
        guard !isRecording else {
            print("[SessionReplay] Already recording")
            return
        }

        print("[SessionReplay] Starting session...")

        ensureStorageDirectory()

        currentSession = ReplaySession()
        screenTransitions = []
        isRecording = true
        lastCaptureTime = 0
        frameBuffer.removeAll()
        viewTreeHash = 0

        if let session = currentSession {
            let videoPath = config.storageDirectory
                .appendingPathComponent("\(session.sessionId)_segment0.mp4")
            let screenSize = UIScreen.main.bounds.size
            let captureSize = CGSize(
                width: screenSize.width * config.captureScale,
                height: screenSize.height * config.captureScale
            )

            videoWriter = VideoWriter(
                outputURL: videoPath,
                size: captureSize,
                bitrate: config.videoBitrate
            )
            videoWriter?.startWriting()

            currentSession?.videoSegments.append(videoPath.lastPathComponent)

            // Start logging capture
            SessionLogger.shared.startCapture(sessionId: session.sessionId, startTime: session.startTime)
        }

        startDisplayLink()

        print("[SessionReplay] Session started: \(currentSession?.sessionId ?? "unknown")")
    }

    /// Stop the current recording session
    public func stopSession() {
        guard isRecording else { return }

        print("[SessionReplay] Stopping session...")

        isRecording = false
        stopDisplayLink()

        // Stop logging
        let logData = SessionLogger.shared.stopCapture()

        videoWriter?.finishWriting { [weak self] in
            guard let self = self else { return }

            self.currentSession?.endTime = Date()

            if let session = self.currentSession {
                self.saveSessionMetadata(session, logData: logData)
            }

            print("[SessionReplay] Session stopped. Frames captured: \(self.currentSession?.frameCount ?? 0)")
            print("[SessionReplay] Touch events: \(self.currentSession?.touchEvents?.count ?? 0)")
        }
    }

    // MARK: - Touch Recording

    /// Record a touch event
    public func recordTouchEvent(_ touch: UITouch, in window: UIWindow) {
        guard isRecording, config.captureTouches else { return }

        let location = touch.location(in: window)
        let timestamp = touch.timestamp

        let event = CapturedTouchEvent(
            timestamp: timestamp,
            phase: touch.phase.rawValue,
            location: location,
            tapCount: touch.tapCount,
            force: touch.force,
            radius: touch.majorRadius,
            type: touch.type.rawValue,
            screenName: currentScreenName
        )

        currentSession?.touchEvents?.append(event)

        if touch.phase == .began || touch.phase == .ended {
            print("[SessionReplay] Touch \(event.phaseDescription) at \(location)")
        }
    }

    // MARK: - Screen Tracking

    /// Track screen/view transitions
    public func trackScreen(_ screenName: String) {
        guard isRecording else { return }

        let timestamp = Date().timeIntervalSince(currentSession?.startTime ?? Date()) * 1000
        let transition = ScreenTransition(
            timestamp: timestamp,
            fromScreen: currentScreenName,
            toScreen: screenName
        )

        screenTransitions.append(transition)
        currentScreenName = screenName

        print("[SessionReplay] Screen viewed: \(screenName)")
    }

    // MARK: - Session Management

    /// Get all saved sessions
    public func getSavedSessions() -> [SessionReplayData] {
        let fileManager = FileManager.default
        let directory = config.storageDirectory

        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> SessionReplayData? in
                guard let data = try? Data(contentsOf: url) else {
                    print("[SessionReplay] Failed to read: \(url.lastPathComponent)")
                    return nil
                }
                do {
                    let session = try decoder.decode(SessionReplayData.self, from: data)
                    return session
                } catch {
                    print("[SessionReplay] Failed to decode \(url.lastPathComponent): \(error)")
                    return nil
                }
            }
            .sorted { $0.startTime > $1.startTime }
    }

    /// Get video URL for a session
    public func getVideoURL(for session: SessionReplayData, segmentIndex: Int = 0) -> URL? {
        guard segmentIndex < session.videoSegments.count else { return nil }
        return config.storageDirectory.appendingPathComponent(session.videoSegments[segmentIndex])
    }

    /// Get JSON metadata URL for a session
    public func getJSONURL(for session: SessionReplayData) -> URL? {
        return config.storageDirectory.appendingPathComponent("\(session.sessionId).json")
    }

    /// Delete a session
    public func deleteSession(_ session: SessionReplayData) {
        let fileManager = FileManager.default

        for segment in session.videoSegments {
            let path = config.storageDirectory.appendingPathComponent(segment)
            try? fileManager.removeItem(at: path)
        }

        let metadataPath = config.storageDirectory.appendingPathComponent("\(session.sessionId).json")
        try? fileManager.removeItem(at: metadataPath)
    }

    // MARK: - Private Methods

    private func ensureStorageDirectory() {
        let fileManager = FileManager.default
        let directoryPath = config.storageDirectory.path

        if !fileManager.fileExists(atPath: directoryPath) {
            do {
                try fileManager.createDirectory(
                    at: config.storageDirectory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                print("[SessionReplay] Created storage directory: \(directoryPath)")
            } catch {
                print("[SessionReplay] Failed to create storage directory: \(error.localizedDescription)")
            }
        }

        // Verify the directory is writable
        if !fileManager.isWritableFile(atPath: directoryPath) {
            print("[SessionReplay] Warning: Storage directory is not writable: \(directoryPath)")
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                // Optionally auto-start
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.stopSession()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.stopSession()
            }
            .store(in: &cancellables)
    }

    private func startDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkFired))
        displayLink?.preferredFramesPerSecond = config.captureFrameRate
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func displayLinkFired(_ link: CADisplayLink) {
        guard isRecording else { return }

        let targetInterval = 1.0 / Double(config.captureFrameRate)
        guard link.timestamp - lastCaptureTime >= targetInterval else { return }

        lastCaptureTime = link.timestamp
        captureScreenshot()
    }

    private func captureScreenshot() {
        guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) else {
            return
        }

        let newHash = computeViewTreeHash(window)
        guard newHash != viewTreeHash || viewTreeHash == 0 else {
            return
        }
        viewTreeHash = newHash

        // Collect sensitive view frames before capturing
        var sensitiveFrames: [CGRect] = []
        if config.maskSensitiveViews {
            sensitiveFrames = collectSensitiveViewFrames(in: window)
        }

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { context in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)

            // Draw masks over sensitive views
            if config.maskSensitiveViews && !sensitiveFrames.isEmpty {
                drawSensitiveMasks(in: context.cgContext, frames: sensitiveFrames)
            }

            if config.showTouchIndicators {
                drawTouchIndicators(in: context.cgContext, bounds: window.bounds)
            }
        }

        if let count = currentSession?.frameCount {
            currentSession?.frameCount! += 1
        }
        captureQueue.async { [weak self] in
            self?.processFrame(image)
        }
    }

    /// Collect frames of all sensitive views that should be masked
    private func collectSensitiveViewFrames(in view: UIView) -> [CGRect] {
        var frames: [CGRect] = []
        collectSensitiveFramesRecursive(view, rootView: view, frames: &frames)
        return frames
    }

    private func collectSensitiveFramesRecursive(_ view: UIView, rootView: UIView, frames: inout [CGRect]) {
        // Check if this view should be masked
        if shouldMaskView(view) {
            let frameInRoot = view.convert(view.bounds, to: rootView)
            frames.append(frameInRoot)
            return // Don't check children of masked views
        }

        // Recurse into subviews
        for subview in view.subviews {
            collectSensitiveFramesRecursive(subview, rootView: rootView, frames: &frames)
        }
    }

    private func shouldMaskView(_ view: UIView) -> Bool {
        // Check manual sensitive marking
        if view.isSensitive {
            return true
        }

        // Check if it's a MaskedView
        if let maskable = view as? SessionReplayMaskable, maskable.shouldMaskInReplay {
            return true
        }

        // Auto-mask secure text fields (password fields)
        if config.autoMaskSecureTextFields {
            if let textField = view as? UITextField, textField.isSecureTextEntry {
                return true
            }
        }

        // Auto-mask regular text fields
        if config.autoMaskTextFields {
            if view is UITextField || view is UITextView {
                return true
            }
        }

        // Check custom view classes
        let viewClassName = String(describing: type(of: view))
        if config.autoMaskViewClasses.contains(viewClassName) {
            return true
        }

        return false
    }

    private func drawSensitiveMasks(in context: CGContext, frames: [CGRect]) {
        context.setFillColor(config.sensitiveViewMaskColor.cgColor)

        for frame in frames {
            context.fill(frame)

            // Draw a small "masked" indicator
            let iconSize: CGFloat = min(frame.width, frame.height, 24)
            if iconSize >= 16 {
                context.setFillColor(UIColor.white.withAlphaComponent(0.5).cgColor)
                let iconRect = CGRect(
                    x: frame.midX - iconSize / 2,
                    y: frame.midY - iconSize / 2,
                    width: iconSize,
                    height: iconSize
                )
                context.fillEllipse(in: iconRect)
            }
        }
    }

    private func computeViewTreeHash(_ view: UIView) -> Int {
        var hasher = Hasher()
        computeViewHash(view, into: &hasher)
        return hasher.finalize()
    }

    private func computeViewHash(_ view: UIView, into hasher: inout Hasher) {
        hasher.combine(view.frame.origin.x)
        hasher.combine(view.frame.origin.y)
        hasher.combine(view.frame.size.width)
        hasher.combine(view.frame.size.height)
        hasher.combine(view.isHidden)
        hasher.combine(view.alpha)
        if let label = view as? UILabel {
            hasher.combine(label.text)
        }

        for subview in view.subviews {
            computeViewHash(subview, into: &hasher)
        }
    }

    private func drawTouchIndicators(in context: CGContext, bounds: CGRect) {
        guard let touches = currentSession?.touchEvents?.suffix(10) else { return }

        let now = Date().timeIntervalSinceReferenceDate

        for touch in touches {
            let touchAge = now - (currentSession?.startTime.timeIntervalSinceReferenceDate ?? 0) - touch.timestamp
            guard touchAge < 0.5 else { continue }

            let alpha = max(0, 1.0 - touchAge * 2)

            context.setFillColor(UIColor.red.withAlphaComponent(CGFloat(alpha) * 0.5).cgColor)
            context.setStrokeColor(UIColor.red.withAlphaComponent(CGFloat(alpha)).cgColor)
            context.setLineWidth(2)

            let radius: CGFloat = 20
            let rect = CGRect(
                x: touch.location.x - radius,
                y: touch.location.y - radius,
                width: radius * 2,
                height: radius * 2
            )

            context.fillEllipse(in: rect)
            context.strokeEllipse(in: rect)
        }
    }

    private func processFrame(_ image: UIImage) {
        let scaledImage: UIImage
        if config.captureScale < 1.0 {
            let newSize = CGSize(
                width: image.size.width * config.captureScale,
                height: image.size.height * config.captureScale
            )
            let renderer = UIGraphicsImageRenderer(size: newSize)
            scaledImage = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        } else {
            scaledImage = image
        }

        guard let jpegData = scaledImage.jpegData(compressionQuality: config.jpegCompressionQuality) else {
            return
        }

        guard let compressedImage = UIImage(data: jpegData) else { return }

        videoWriter?.addFrame(compressedImage)
    }

    private func saveSessionMetadata(_ session: ReplaySession, logData: SessionLogData?) {
        let metadata = SessionMetadata(
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "",
            osVersion: UIDevice.current.systemVersion,
            deviceModel: getDeviceModel(),
            deviceId: UIDevice.current.identifierForVendor?.uuidString,
            locale: Locale.current.identifier,
            timezone: TimeZone.current.identifier
        )

        // Convert touch events
        let touches = session.touchEvents

        let sessionData = SessionReplayData(
            sessionId: session.sessionId,
            startTime: session.startTime,
            endTime: session.endTime ?? Date(),
            durationMs: (session.endTime ?? Date()).timeIntervalSince(session.startTime) * 1000,
            videoSegments: session.videoSegments,
            frameCount: session.frameCount ?? 0,
            touches: touches ?? [],
            logs: logData?.logs ?? [],
            networkRequests: logData?.networkRequests ?? [],
            screenTransitions: screenTransitions,
            metadata: metadata
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        guard let data = try? encoder.encode(sessionData) else { return }

        let path = config.storageDirectory.appendingPathComponent("\(session.sessionId).json")
        try? data.write(to: path)

        print("[SessionReplay] Session metadata saved to: \(path)")
    }

    private func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        return machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
    }
}

// MARK: - Touch Swizzling

private var swizzled = false

extension SessionReplayManager {

    func setupSwizzling() {
        guard !swizzled else { return }
        swizzled = true
        let originalSelector = #selector(UIWindow.sendEvent(_:))
        let swizzledSelector = #selector(UIWindow.sr_sendEvent(_:))

        guard let originalMethod = class_getInstanceMethod(UIWindow.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(UIWindow.self, swizzledSelector) else {
            print("[SessionReplay] Failed to swizzle sendEvent")
            return
        }

        method_exchangeImplementations(originalMethod, swizzledMethod)
        print("[SessionReplay] Touch event swizzling enabled")
    }
}

extension UIWindow {

    @objc func sr_sendEvent(_ event: UIEvent) {
        if let touches = event.allTouches {
            for touch in touches {
                SessionReplayManager.shared.recordTouchEvent(touch, in: self)
            }
        }
        sr_sendEvent(event)
    }
}

#endif
