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

    // MARK: - User Identification

    /// Custom user info dictionary for identifying users in session data
    public private(set) var userInfo: [String: String] = [:]

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

    /// Timer for crash recovery saves
    private var crashRecoveryTimer: Timer?

    // MARK: - Initialization

    private init() {
        setupNotifications()
        setupTouchCapture()
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

        // Auto-start if configured
        if config.autoStartOnLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.startSession()
            }
        }
    }

    // MARK: - User Identification

    /// Set custom user info for session identification
    /// - Parameter info: Dictionary of user info (e.g., ["userId": "123", "email": "user@example.com"])
    public func setUserInfo(_ info: [String: String]) {
        self.userInfo = info
        if config.debugLogging {
            print("[SessionReplay] User info set: \(info.keys.joined(separator: ", "))")
        }
    }

    /// Update a single user info value
    public func setUserInfo(key: String, value: String) {
        self.userInfo[key] = value
    }

    /// Clear all user info
    public func clearUserInfo() {
        self.userInfo.removeAll()
    }

    /// Identify user with common fields
    public func identifyUser(userId: String, email: String? = nil, name: String? = nil, additionalInfo: [String: String]? = nil) {
        var info: [String: String] = ["userId": userId]
        if let email = email { info["email"] = email }
        if let name = name { info["name"] = name }
        if let additional = additionalInfo {
            info.merge(additional) { _, new in new }
        }
        setUserInfo(info)
    }

    // MARK: - Session Lifecycle

    /// Start a new recording session
    public func startSession() {
        guard !isRecording else {
            print("[SessionReplay] Already recording")
            return
        }

        let mode = config.enableVideoRecording ? "video + logs" : "logs only"
        print("[SessionReplay] Starting session (\(mode))...")

        ensureStorageDirectory()

        currentSession = ReplaySession()
        screenTransitions = []
        isRecording = true
        lastCaptureTime = 0
        frameBuffer.removeAll()
        viewTreeHash = 0

        if let session = currentSession {
            // Only setup video recording if enabled
            if config.enableVideoRecording {
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
            }

            // Start logging capture (always enabled)
            SessionLogger.shared.startCapture(sessionId: session.sessionId, startTime: session.startTime)
        }

        // Only start display link for video recording
        if config.enableVideoRecording {
            startDisplayLink()
        }

        // Start crash recovery timer if enabled
        if config.enableCrashRecovery {
            startCrashRecoveryTimer()
        }

        print("[SessionReplay] Session started: \(currentSession?.sessionId ?? "unknown")")
    }

    /// Stop the current recording session
    public func stopSession() {
        stopSession(completion: nil)
    }

    /// Stop the current recording session with a completion handler
    /// - Parameter completion: Called on the main thread after the session is fully saved
    public func stopSession(completion: (() -> Void)?) {
        guard isRecording else {
            completion.map { cb in DispatchQueue.main.async { cb() } }
            return
        }

        if config.debugLogging {
            print("[SessionReplay] Stopping session...")
        }

        isRecording = false
        stopDisplayLink()
        stopCrashRecoveryTimer()

        // Stop logging
        let logData = SessionLogger.shared.stopCapture()

        // If video recording is enabled, finish video then save
        if config.enableVideoRecording {
            videoWriter?.finishWriting { [weak self] in
                guard let self = self else {
                    DispatchQueue.main.async { completion?() }
                    return
                }

                self.currentSession?.endTime = Date()

                if let session = self.currentSession {
                    self.saveSessionMetadata(session, logData: logData)
                    self.cleanupCrashRecoveryFile(sessionId: session.sessionId)
                }

                if self.config.debugLogging {
                    print("[SessionReplay] Session stopped. Frames captured: \(self.currentSession?.frameCount ?? 0)")
                    print("[SessionReplay] Touch events: \(self.currentSession?.touchEvents?.count ?? 0)")
                }

                DispatchQueue.main.async { completion?() }
            }
        } else {
            // Logs-only mode - save immediately
            currentSession?.endTime = Date()

            if let session = currentSession {
                saveSessionMetadata(session, logData: logData)
                cleanupCrashRecoveryFile(sessionId: session.sessionId)
            }

            if config.debugLogging {
                print("[SessionReplay] Session stopped (logs only). Log entries: \(logData?.logs.count ?? 0)")
                print("[SessionReplay] Network requests: \(logData?.networkRequests.count ?? 0)")
            }

            DispatchQueue.main.async { completion?() }
        }
    }

    /// Stop the current recording session (async version)
    @available(iOS 13.0, *)
    public func stopSessionAsync() async {
        await withCheckedContinuation { continuation in
            stopSession {
                continuation.resume()
            }
        }
    }

    /// Emergency stop - saves session immediately (for crash/terminate scenarios)
    private func emergencyStopSession() {
        guard isRecording else { return }

        if config.debugLogging {
            print("[SessionReplay] Emergency stop - saving session...")
        }

        isRecording = false
        stopDisplayLink()
        stopCrashRecoveryTimer()

        // Get current log data
        let logData = SessionLogger.shared.stopCapture()

        // Finish video writing synchronously if video is enabled
        if config.enableVideoRecording {
            videoWriter?.finishWritingSync()
        }

        currentSession?.endTime = Date()

        if let session = currentSession {
            saveSessionMetadata(session, logData: logData)
            cleanupCrashRecoveryFile(sessionId: session.sessionId)
        }

        if config.debugLogging {
            print("[SessionReplay] Emergency save completed")
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
        // Touch logging removed - was too verbose for console
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
        // App entering foreground - optionally auto-start
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.config.autoStartOnLaunch && !self.isRecording {
                    self.startSession()
                }
            }
            .store(in: &cancellables)

        // App entering background - optionally auto-stop
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.config.autoStopOnBackground && self.isRecording {
                    self.stopSession()
                }
            }
            .store(in: &cancellables)

        // App terminating - always try to save
        NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.config.autoStopOnTerminate && self.isRecording {
                    self.emergencyStopSession()
                }
            }
            .store(in: &cancellables)

        // Memory warning - optionally save checkpoint
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.isRecording && self.config.enableCrashRecovery {
                    self.saveCrashRecoveryData()
                    if self.config.debugLogging {
                        print("[SessionReplay] Memory warning - crash recovery data saved")
                    }
                }
            }
            .store(in: &cancellables)

        // Register for uncaught exception handling
        setupCrashHandler()
    }

    private func setupCrashHandler() {
        // Set up signal handlers for crashes
        let signals: [Int32] = [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGPIPE, SIGTRAP]
        for sig in signals {
            signal(sig) { signal in
                // Save crash recovery data synchronously
                SessionReplayManager.shared.saveCrashRecoveryData()
            }
        }

        // Set uncaught exception handler
        NSSetUncaughtExceptionHandler { exception in
            SessionReplayManager.shared.saveCrashRecoveryData()
        }
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

    // MARK: - Crash Recovery

    private func startCrashRecoveryTimer() {
        stopCrashRecoveryTimer()
        crashRecoveryTimer = Timer.scheduledTimer(withTimeInterval: config.crashRecoveryInterval, repeats: true) { [weak self] _ in
            self?.saveCrashRecoveryData()
        }
    }

    private func stopCrashRecoveryTimer() {
        crashRecoveryTimer?.invalidate()
        crashRecoveryTimer = nil
    }

    /// Save current session state for crash recovery
    func saveCrashRecoveryData() {
        guard isRecording, let session = currentSession else { return }

        let recoveryData: [String: Any] = [
            "sessionId": session.sessionId,
            "startTime": session.startTime.timeIntervalSince1970,
            "lastUpdateTime": Date().timeIntervalSince1970,
            "frameCount": session.frameCount ?? 0,
            "touchCount": session.touchEvents?.count ?? 0,
            "videoSegments": session.videoSegments,
            "userInfo": userInfo
        ]

        let recoveryPath = config.storageDirectory.appendingPathComponent("\(session.sessionId)_recovery.plist")

        do {
            let data = try PropertyListSerialization.data(fromPropertyList: recoveryData, format: .binary, options: 0)
            try data.write(to: recoveryPath)
        } catch {
            if config.debugLogging {
                print("[SessionReplay] Failed to save crash recovery data: \(error)")
            }
        }
    }

    private func cleanupCrashRecoveryFile(sessionId: String) {
        let recoveryPath = config.storageDirectory.appendingPathComponent("\(sessionId)_recovery.plist")
        try? FileManager.default.removeItem(at: recoveryPath)
    }

    /// Check for incomplete sessions from previous crashes
    public func recoverIncompleteSessions() -> [String] {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: config.storageDirectory, includingPropertiesForKeys: nil) else {
            return []
        }

        let recoveryFiles = files.filter { $0.pathExtension == "plist" && $0.lastPathComponent.contains("_recovery") }
        var recoveredSessionIds: [String] = []

        for file in recoveryFiles {
            if let data = try? Data(contentsOf: file),
               let recoveryData = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let sessionId = recoveryData["sessionId"] as? String {
                recoveredSessionIds.append(sessionId)
                if config.debugLogging {
                    print("[SessionReplay] Found incomplete session: \(sessionId)")
                }
            }
        }

        return recoveredSessionIds
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
            timezone: TimeZone.current.identifier,
            userInfo: userInfo.isEmpty ? nil : userInfo
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
            metadata: metadata,
            userInfo: userInfo.isEmpty ? nil : userInfo
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        guard let data = try? encoder.encode(sessionData) else { return }

        let path = config.storageDirectory.appendingPathComponent("\(session.sessionId).json")
        try? data.write(to: path)

        if config.debugLogging {
            print("[SessionReplay] Session metadata saved to: \(path)")
        }
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

// MARK: - Touch Capture

private var touchCaptureInstalled = false

extension SessionReplayManager {

    /// Installs passive touch observation on every visible `UIWindow`.
    ///
    /// Earlier versions swizzled `UIWindow.sendEvent(_:)`. That placed the SDK on the
    /// call stack of *every* touch dispatch in the host app, so any `NSException`
    /// raised by UIKit or by app code while handling a touch (for example the
    /// iOS 26 TextKit 2 selection-handle crash in
    /// `-[UITextField _visualSelectionRangeForExtent:forPoint:fromPosition:inDirection:]`)
    /// was attributed to `sr_sendEvent` in crash reports even though the SDK only
    /// forwarded the event. A `UIGestureRecognizer` that never recognizes sees the
    /// same touches without wrapping UIKit's event dispatch, so the SDK no longer
    /// appears in those stacks and cannot interfere with the event pipeline.
    func setupTouchCapture() {
        if Thread.isMainThread {
            installTouchCapture()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.installTouchCapture()
            }
        }
    }

    private func installTouchCapture() {
        guard !touchCaptureInstalled else { return }
        touchCaptureInstalled = true

        // Windows that already exist (SDK configured after makeKeyAndVisible)
        for window in currentApplicationWindows() {
            attachTouchObserver(to: window)
        }

        // Windows that appear later: alerts/toasts in custom windows, keyboard
        // windows, additional scenes, or the main window when the SDK is
        // configured before makeKeyAndVisible.
        NotificationCenter.default.publisher(for: UIWindow.didBecomeVisibleNotification)
            .compactMap { $0.object as? UIWindow }
            .sink { [weak self] window in
                self?.attachTouchObserver(to: window)
            }
            .store(in: &cancellables)
    }

    private func currentApplicationWindows() -> [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
    }

    private func attachTouchObserver(to window: UIWindow) {
        let alreadyAttached = window.gestureRecognizers?.contains { $0 is SessionReplayTouchObserver } ?? false
        guard !alreadyAttached else { return }
        window.addGestureRecognizer(SessionReplayTouchObserver())
    }
}

/// A gesture recognizer that observes every touch delivered to its window but
/// never recognizes, so it cannot cancel, delay, or block any other gesture or
/// touch handling in the host app.
final class SessionReplayTouchObserver: UIGestureRecognizer, UIGestureRecognizerDelegate {

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        requiresExclusiveTouchType = false
        allowedTouchTypes = [
            UITouch.TouchType.direct,
            .indirect,
            .pencil,
            .indirectPointer
        ].map { NSNumber(value: $0.rawValue) }
        delegate = self
    }

    // MARK: Touch observation

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        record(touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        record(touches)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        record(touches)
        failIfSequenceFinished(event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        record(touches)
        failIfSequenceFinished(event)
    }

    private func record(_ touches: Set<UITouch>) {
        guard let window = view as? UIWindow ?? view?.window else { return }
        for touch in touches {
            SessionReplayManager.shared.recordTouchEvent(touch, in: window)
        }
    }

    /// Only give up once every touch in this sequence has lifted. Failing while
    /// other fingers are still down would stop UIKit delivering their moves to us.
    private func failIfSequenceFinished(_ event: UIEvent) {
        let stillActive = event.touches(for: self)?.contains {
            $0.phase != .ended && $0.phase != .cancelled
        } ?? false
        if !stillActive && state == .possible {
            state = .failed
        }
    }

    // MARK: UIGestureRecognizerDelegate — never block anything

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive press: UIPress) -> Bool {
        false
    }
}

#endif
