//
//  SessionLogger.swift
//  SessionReplaySDK
//
//  Console log and network request capture for session replay.
//  Designed to integrate with SessionReplayManager lifecycle.
//
//  Created by AlmoutasemNabil on 2026.
//  Copyright © 2026 AlmoutasemNabil. All rights reserved.
//
//  This source code is licensed under the MIT license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

// MARK: - Session Logger

/// Main class for capturing console logs and network requests during a session.
public final class SessionLogger {

    public static let shared = SessionLogger()

    // MARK: - Properties

    private var config = SessionLoggerConfig()
    private var isCapturing = false
    private var sessionStartTime: Date?
    private var sessionId: String?

    // Thread-safe storage
    private let logQueue = DispatchQueue(label: "com.sessionreplay.logger", qos: .utility)
    private var logEntries: [LogEntry] = []
    private var networkEntries: [NetworkEntry] = []

    // Console capture
    private var stdoutCapture: ConsoleCapture?
    private var stderrCapture: ConsoleCapture?

    // Limits
    private let maxLogEntries = 10_000
    private let maxNetworkEntries = 1_000

    private init() {}

    // MARK: - Configuration

    /// Configure the logger (call before starting capture)
    public func configure(_ config: SessionLoggerConfig) {
        logQueue.sync {
            self.config = config
        }
    }

    // MARK: - Lifecycle

    /// Start capturing logs and network requests for a session
    public func startCapture(sessionId: String, startTime: Date = Date()) {
        logQueue.sync {
            guard !isCapturing else { return }

            self.sessionId = sessionId
            self.sessionStartTime = startTime
            self.logEntries.removeAll()
            self.networkEntries.removeAll()
            self.isCapturing = true
        }

        if config.captureConsoleLogs {
            startConsoleCapture()
        }

        if config.captureNetworkRequests {
            NetworkInterceptor.shared.startCapture(logger: self)
        }

        log("SessionLogger started for session: \(sessionId)", level: .info, source: "system")
    }

    /// Stop capturing and return all captured data
    public func stopCapture() -> SessionLogData? {
        var data: SessionLogData?

        logQueue.sync {
            guard isCapturing else { return }
            isCapturing = false
        }

        log("SessionLogger stopped", level: .info, source: "system")

        stopConsoleCapture()
        NetworkInterceptor.shared.stopCapture()

        logQueue.sync {
            guard let sessionId = sessionId, let startTime = sessionStartTime else { return }

            data = SessionLogData(
                sessionId: sessionId,
                startTime: startTime,
                endTime: Date(),
                logs: logEntries,
                networkRequests: networkEntries
            )

            self.sessionId = nil
            self.sessionStartTime = nil
        }

        return data
    }

    /// Check if currently capturing
    public var isActive: Bool {
        logQueue.sync { isCapturing }
    }

    // MARK: - Public Access to Logs

    /// Get current logs (for live display during recording)
    public func getLogs() -> [LogEntry] {
        logQueue.sync { logEntries }
    }

    /// Get current network requests (for live display during recording)
    public func getNetworkRequests() -> [NetworkEntry] {
        logQueue.sync { networkEntries }
    }

    // MARK: - Manual Logging API

    /// Log a custom message
    public func log(_ message: String, level: LogLevel = .info, source: String = "custom") {
        guard config.captureConsoleLogs else { return }
        guard level.priority >= config.minimumLogLevel.priority else { return }

        addLogEntry(message: message, level: level, source: source)
    }

    /// Log a debug message
    public func debug(_ message: String) {
        log(message, level: .debug, source: "app")
    }

    /// Log an info message
    public func info(_ message: String) {
        log(message, level: .info, source: "app")
    }

    /// Log a warning message
    public func warning(_ message: String) {
        log(message, level: .warning, source: "app")
    }

    /// Log an error message
    public func error(_ message: String) {
        log(message, level: .error, source: "app")
    }

    // MARK: - Internal: Log Entry Management

    internal func addLogEntry(message: String, level: LogLevel, source: String) {
        logQueue.async { [weak self] in
            guard let self = self, self.isCapturing else { return }
            guard let startTime = self.sessionStartTime else { return }

            var sanitizedMessage = message

            if let sanitizer = self.config.logSanitizer {
                sanitizedMessage = sanitizer(sanitizedMessage)
            }

            if sanitizedMessage.count > self.config.maxLogMessageLength {
                sanitizedMessage = String(sanitizedMessage.prefix(self.config.maxLogMessageLength)) + "... [truncated]"
            }

            let now = Date()
            let entry = LogEntry(
                timestamp: now.timeIntervalSince(startTime) * 1000,
                absoluteTime: now,
                level: level,
                message: sanitizedMessage,
                source: source,
                threadName: Thread.current.name
            )

            self.logEntries.append(entry)

            if self.logEntries.count > self.maxLogEntries {
                self.logEntries.removeFirst(self.logEntries.count - self.maxLogEntries)
            }
        }
    }

    internal func addNetworkEntry(_ entry: NetworkEntry) {
        logQueue.async { [weak self] in
            guard let self = self, self.isCapturing else { return }

            self.networkEntries.append(entry)

            if self.networkEntries.count > self.maxNetworkEntries {
                self.networkEntries.removeFirst(self.networkEntries.count - self.maxNetworkEntries)
            }
        }
    }

    internal func getRelativeTimestamp() -> TimeInterval {
        guard let startTime = sessionStartTime else { return 0 }
        return Date().timeIntervalSince(startTime) * 1000
    }

    internal var currentConfig: SessionLoggerConfig {
        logQueue.sync { config }
    }

    // MARK: - Console Capture

    private func startConsoleCapture() {
        stdoutCapture = ConsoleCapture(fileDescriptor: STDOUT_FILENO) { [weak self] output in
            self?.processConsoleOutput(output, isStderr: false)
        }
        stdoutCapture?.start()

        stderrCapture = ConsoleCapture(fileDescriptor: STDERR_FILENO) { [weak self] output in
            self?.processConsoleOutput(output, isStderr: true)
        }
        stderrCapture?.start()
    }

    private func stopConsoleCapture() {
        stdoutCapture?.stop()
        stderrCapture?.stop()
        stdoutCapture = nil
        stderrCapture = nil
    }

    private func processConsoleOutput(_ output: String, isStderr: Bool) {
        let level = classifyLogLevel(output, isStderr: isStderr)

        guard level.priority >= config.minimumLogLevel.priority else { return }

        let source = isStderr ? "stderr" : "stdout"
        addLogEntry(message: output, level: level, source: source)
    }

    private func classifyLogLevel(_ message: String, isStderr: Bool) -> LogLevel {
        let lowercased = message.lowercased()

        if lowercased.contains("error") ||
           lowercased.contains("exception") ||
           lowercased.contains("fatal") ||
           lowercased.contains("crash") ||
           lowercased.contains("failed") {
            return .error
        }

        if lowercased.contains("warning") ||
           lowercased.contains("warn") ||
           lowercased.contains("deprecated") {
            return .warning
        }

        if lowercased.contains("debug") ||
           lowercased.contains("verbose") {
            return .debug
        }

        if isStderr {
            return .warning
        }

        return .info
    }
}

// MARK: - Console Capture Helper

/// Captures stdout/stderr using Unix pipe redirection
private final class ConsoleCapture {
    private let inputPipe = Pipe()
    private let originalFD: Int32
    private let savedFD: Int32
    private let onOutput: (String) -> Void
    private var isCapturing = false

    init(fileDescriptor: Int32, onOutput: @escaping (String) -> Void) {
        self.originalFD = fileDescriptor
        self.savedFD = dup(fileDescriptor)
        self.onOutput = onOutput
    }

    func start() {
        guard !isCapturing else { return }
        isCapturing = true

        if originalFD == STDOUT_FILENO {
            setvbuf(stdout, nil, _IONBF, 0)
        } else if originalFD == STDERR_FILENO {
            setvbuf(stderr, nil, _IONBF, 0)
        }

        dup2(inputPipe.fileHandleForWriting.fileDescriptor, originalFD)

        inputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }

            let data = handle.availableData
            guard !data.isEmpty else { return }

            if self.savedFD >= 0 {
                data.withUnsafeBytes { bytes in
                    _ = write(self.savedFD, bytes.baseAddress!, data.count)
                }
            }

            if let string = String(data: data, encoding: .utf8) {
                let lines = string.components(separatedBy: .newlines)
                    .filter { !$0.isEmpty }

                for line in lines {
                    self.onOutput(line)
                }
            }
        }
    }

    func stop() {
        guard isCapturing else { return }
        isCapturing = false

        inputPipe.fileHandleForReading.readabilityHandler = nil

        if savedFD >= 0 {
            dup2(savedFD, originalFD)
            close(savedFD)
        }
    }

    deinit {
        stop()
    }
}
