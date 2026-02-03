//
//  SessionReplaySDK.swift
//  SessionReplaySDK
//
//  Main SDK entry point and public API exports.
//
//  Usage:
//  1. Import the SDK: import SessionReplaySDK
//  2. Configure on app launch:
//     SessionReplaySDK.configure(videoConfig: config, logConfig: logConfig)
//  3. Start/stop recording:
//     SessionReplaySDK.startSession()
//     SessionReplaySDK.stopSession()
//  4. Upload sessions:
//     SessionReplaySDK.configureUpload(baseURL: url, apiKey: key)
//     SessionReplaySDK.uploadSession(sessionId: id) { result in ... }
//

import Foundation

/// Main SDK facade providing simplified access to session replay functionality
public enum SessionReplaySDK {

    /// SDK version
    public static let version = "1.0.0"

    // MARK: - Configuration

    /// Configure the SDK with video capture settings
    /// - Parameters:
    ///   - videoConfig: Video capture configuration
    ///   - logConfig: Logging configuration (optional)
    #if canImport(UIKit)
    public static func configure(
        videoConfig: SessionReplayConfig = SessionReplayConfig(),
        logConfig: SessionLoggerConfig = SessionLoggerConfig()
    ) {
        SessionReplayManager.shared.configure(videoConfig, logConfig: logConfig)
    }
    #endif

    /// Configure the upload service
    /// - Parameters:
    ///   - baseURL: The upload endpoint URL
    ///   - apiKey: Optional API key for authentication
    ///   - additionalHeaders: Optional additional headers
    public static func configureUpload(
        baseURL: URL,
        apiKey: String? = nil,
        additionalHeaders: [String: String] = [:]
    ) {
        var config = SessionUploadConfig(baseURL: baseURL, apiKey: apiKey)
        config.additionalHeaders = additionalHeaders
        SessionUploader.shared.configure(config)
    }

    // MARK: - Recording Control

    #if canImport(UIKit)
    /// Start recording a new session
    public static func startSession() {
        SessionReplayManager.shared.startSession()
    }

    /// Stop the current recording session
    public static func stopSession() {
        SessionReplayManager.shared.stopSession()
    }

    /// Check if currently recording
    public static var isRecording: Bool {
        SessionReplayManager.shared.isRecording
    }

    /// Get the current session (if recording)
    public static var currentSession: ReplaySession? {
        SessionReplayManager.shared.currentSession
    }
    #endif

    // MARK: - Session Management

    #if canImport(UIKit)
    /// Get all saved sessions
    public static func getSavedSessions() -> [SessionReplayData] {
        SessionReplayManager.shared.getSavedSessions()
    }

    /// Delete a session
    public static func deleteSession(_ session: SessionReplayData) {
        SessionReplayManager.shared.deleteSession(session)
    }

    /// Delete a session by ID
    public static func deleteSession(sessionId: String) {
        let sessions = getSavedSessions()
        if let session = sessions.first(where: { $0.sessionId == sessionId }) {
            deleteSession(session)
        }
    }

    /// Get the video URL for a session
    public static func getVideoURL(for sessionId: String) -> URL? {
        let sessions = getSavedSessions()
        guard let session = sessions.first(where: { $0.sessionId == sessionId }) else {
            return nil
        }
        return SessionReplayManager.shared.getVideoURL(for: session)
    }

    /// Get the JSON metadata URL for a session
    public static func getJSONURL(for sessionId: String) -> URL? {
        let sessions = getSavedSessions()
        guard let session = sessions.first(where: { $0.sessionId == sessionId }) else {
            return nil
        }
        return SessionReplayManager.shared.getJSONURL(for: session)
    }
    #endif

    // MARK: - Upload

    /// Upload a session by ID
    /// - Parameters:
    ///   - sessionId: The session ID to upload
    ///   - completion: Completion handler with result
    public static func uploadSession(
        sessionId: String,
        completion: @escaping (Result<SessionUploadResponse, Error>) -> Void
    ) {
        SessionUploader.shared.uploadSession(sessionId: sessionId, completion: completion)
    }

    /// Upload video and JSON files directly
    /// - Parameters:
    ///   - sessionId: Session identifier
    ///   - videoURL: Local URL of the video file
    ///   - jsonURL: Local URL of the JSON metadata file
    ///   - completion: Completion handler with result
    public static func uploadFiles(
        sessionId: String,
        videoURL: URL,
        jsonURL: URL,
        completion: @escaping (Result<SessionUploadResponse, Error>) -> Void
    ) {
        SessionUploader.shared.uploadFiles(
            sessionId: sessionId,
            videoURL: videoURL,
            jsonURL: jsonURL,
            completion: completion
        )
    }

    /// Upload all pending sessions
    /// - Parameter completion: Completion handler with results for each session
    public static func uploadAllSessions(
        completion: @escaping ([(String, Result<SessionUploadResponse, Error>)]) -> Void
    ) {
        SessionUploader.shared.uploadAllPendingSessions(completion: completion)
    }

    /// Cancel an ongoing upload
    public static func cancelUpload(sessionId: String) {
        SessionUploader.shared.cancelUpload(sessionId: sessionId)
    }

    // MARK: - Logging

    /// Log a custom message to the session
    public static func log(_ message: String, level: LogLevel = .info) {
        SessionLogger.shared.log(message, level: level, source: "app")
    }

    /// Log a debug message
    public static func debug(_ message: String) {
        SessionLogger.shared.debug(message)
    }

    /// Log an info message
    public static func info(_ message: String) {
        SessionLogger.shared.info(message)
    }

    /// Log a warning message
    public static func warning(_ message: String) {
        SessionLogger.shared.warning(message)
    }

    /// Log an error message
    public static func error(_ message: String) {
        SessionLogger.shared.error(message)
    }

    // MARK: - Screen Tracking

    #if canImport(UIKit)
    /// Track a screen view
    public static func trackScreen(_ screenName: String) {
        SessionReplayManager.shared.trackScreen(screenName)
    }
    #endif
}

// MARK: - Re-exports

// Core Models
public typealias Config = SessionReplayConfig
public typealias LogConfig = SessionLoggerConfig
public typealias Session = ReplaySession
public typealias Touch = CapturedTouchEvent
public typealias Log = LogEntry
public typealias Network = NetworkEntry
