//
//  Models.swift
//  SessionReplaySDK
//
//  Data models for session replay capture.
//
//  Created by AlmoutasemNabil on 2026.
//  Copyright © 2026 AlmoutasemNabil. All rights reserved.
//
//  This source code is licensed under the MIT license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Configuration

/// Configuration options for session replay capture
public struct SessionReplayConfig {
    /// Frames per second to capture (default: 1 fps for efficiency)
    public var captureFrameRate: Int = 1

    /// JPEG compression quality (0.0 - 1.0, lower = smaller files)
    public var jpegCompressionQuality: CGFloat = 0.3

    /// Scale factor for captured images (1.0 = full resolution)
    public var captureScale: CGFloat = 1.0

    /// Video bitrate in bits per second
    public var videoBitrate: Int = 75_000

    /// Maximum local storage size in bytes (default: 50MB)
    public var maxStorageSize: Int = 50 * 1024 * 1024

    /// Duration for video segments in seconds
    public var segmentDuration: TimeInterval = 10.0

    /// Whether to capture touch events
    public var captureTouches: Bool = true

    /// Whether to show touch indicators on captured frames
    public var showTouchIndicators: Bool = true

    /// Whether to mask sensitive views (marked with `markAsSensitive()`)
    public var maskSensitiveViews: Bool = true

    /// Color used to mask sensitive content
    public var sensitiveViewMaskColor: UIColor = .gray

    /// Whether to automatically mask text input fields
    public var autoMaskTextFields: Bool = true

    /// Whether to automatically mask secure text entries (password fields)
    public var autoMaskSecureTextFields: Bool = true

    /// View classes to automatically mask (in addition to manually marked views)
    public var autoMaskViewClasses: [String] = []

    /// Directory for storing session recordings.
    /// Can be customized to support App Groups for sharing data between app and extensions.
    ///
    /// Example usage with App Groups:
    /// ```swift
    /// var config = SessionReplayConfig()
    /// if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.yourapp") {
    ///     config.storageDirectory = containerURL.appendingPathComponent("SessionReplays", isDirectory: true)
    /// }
    /// SessionReplaySDK.configure(videoConfig: config)
    /// ```
    public var storageDirectory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("SessionReplays", isDirectory: true)

    public init() {}
}

/// Configuration for session logging (console and network capture)
public struct SessionLoggerConfig {
    /// Enable/disable console log capture
    public var captureConsoleLogs: Bool = true

    /// Enable/disable network request capture
    public var captureNetworkRequests: Bool = true

    /// Minimum log level to capture
    public var minimumLogLevel: LogLevel = .debug

    /// Maximum log message length (truncated if exceeded)
    public var maxLogMessageLength: Int = 2000

    /// Maximum request/response body size to capture (in bytes)
    public var maxBodySize: Int = 100_000  // 100KB

    /// Headers to redact from network capture (case-insensitive)
    public var redactedHeaders: Set<String> = [
        "authorization", "cookie", "set-cookie",
        "x-api-key", "api-key", "apikey",
        "x-auth-token", "x-access-token"
    ]

    /// URL patterns to exclude from network capture (regex)
    public var excludedURLPatterns: [String] = []

    /// Custom log sanitizer closure
    public var logSanitizer: ((String) -> String)? = nil

    public init() {}
}

// MARK: - Session Data Models

/// A captured touch event
public struct CapturedTouchEvent: Codable {
    public let timestamp: TimeInterval
    public let phase: Int
    public let location: CGPoint
    public let tapCount: Int
    public let force: CGFloat
    public let radius: CGFloat
    public let type: Int
    public let screenName: String?

    public init(
        timestamp: TimeInterval,
        phase: Int,
        location: CGPoint,
        tapCount: Int,
        force: CGFloat,
        radius: CGFloat,
        type: Int,
        screenName: String? = nil
    ) {
        self.timestamp = timestamp
        self.phase = phase
        self.location = location
        self.tapCount = tapCount
        self.force = force
        self.radius = radius
        self.type = type
        self.screenName = screenName
    }

    #if canImport(UIKit)
    public var phaseDescription: String {
        switch UITouch.Phase(rawValue: phase) {
        case .began: return "began"
        case .moved: return "moved"
        case .ended: return "ended"
        case .cancelled: return "cancelled"
        case .stationary: return "stationary"
        case .regionEntered: return "regionEntered"
        case .regionMoved: return "regionMoved"
        case .regionExited: return "regionExited"
        default: return "unknown"
        }
    }
    #endif
}

/// A recorded session with video and events
public struct ReplaySession: Codable, Identifiable {
    public let sessionId: String
    public let startTime: Date
    public var endTime: Date?
    public var touchEvents: [CapturedTouchEvent]?
    public var videoSegments: [String]
    public var frameCount: Int?

    public var id: String { sessionId }

    public init(sessionId: String = UUID().uuidString) {
        self.sessionId = sessionId
        self.startTime = Date()
        self.touchEvents = []
        self.videoSegments = []
        self.frameCount = 0
    }
}

// MARK: - Logging Models

/// Severity level for captured logs
public enum LogLevel: String, Codable, Comparable {
    case debug = "debug"
    case info = "info"
    case warning = "warning"
    case error = "error"

    public var priority: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warning: return 2
        case .error: return 3
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.priority < rhs.priority
    }
}

/// A single captured log entry
public struct LogEntry: Codable {
    public let timestamp: TimeInterval
    public let absoluteTime: Date
    public let level: LogLevel
    public let message: String
    public let source: String
    public let threadName: String?

    public init(
        timestamp: TimeInterval,
        absoluteTime: Date,
        level: LogLevel,
        message: String,
        source: String,
        threadName: String? = nil
    ) {
        self.timestamp = timestamp
        self.absoluteTime = absoluteTime
        self.level = level
        self.message = message
        self.source = source
        self.threadName = threadName
    }
}

/// A captured network request with response
public struct NetworkEntry: Codable {
    public let id: String
    public let timestamp: TimeInterval
    public let absoluteTime: Date

    // Request
    public let method: String
    public let url: String
    public let requestHeaders: [String: String]?
    public let requestBody: String?
    public let requestBodySize: Int?

    // Response
    public let statusCode: Int?
    public let responseHeaders: [String: String]?
    public let responseBody: String?
    public let responseBodySize: Int?

    // Timing
    public let duration: TimeInterval?
    public let error: String?

    public init(
        id: String,
        timestamp: TimeInterval,
        absoluteTime: Date,
        method: String,
        url: String,
        requestHeaders: [String: String]? = nil,
        requestBody: String? = nil,
        requestBodySize: Int? = nil,
        statusCode: Int? = nil,
        responseHeaders: [String: String]? = nil,
        responseBody: String? = nil,
        responseBodySize: Int? = nil,
        duration: TimeInterval? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.absoluteTime = absoluteTime
        self.method = method
        self.url = url
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.requestBodySize = requestBodySize
        self.statusCode = statusCode
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody
        self.responseBodySize = responseBodySize
        self.duration = duration
        self.error = error
    }

    /// Curl-like representation
    public var curlCommand: String {
        var curl = "curl -X \(method)"

        if let headers = requestHeaders {
            for (key, value) in headers {
                curl += " -H '\(key): \(value)'"
            }
        }

        if let body = requestBody, !body.isEmpty {
            curl += " -d '\(body)'"
        }

        curl += " '\(url)'"
        return curl
    }
}

/// Screen transition event
public struct ScreenTransition: Codable {
    public let timestamp: TimeInterval
    public let fromScreen: String?
    public let toScreen: String

    public init(timestamp: TimeInterval, fromScreen: String?, toScreen: String) {
        self.timestamp = timestamp
        self.fromScreen = fromScreen
        self.toScreen = toScreen
    }
}

/// Device and app metadata
public struct SessionMetadata: Codable {
    public let appVersion: String
    public let buildNumber: String
    public let osVersion: String
    public let deviceModel: String
    public let deviceId: String?
    public let locale: String
    public let timezone: String

    public init(
        appVersion: String,
        buildNumber: String,
        osVersion: String,
        deviceModel: String,
        deviceId: String?,
        locale: String,
        timezone: String
    ) {
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.deviceId = deviceId
        self.locale = locale
        self.timezone = timezone
    }
}

// MARK: - Complete Session Data

/// Complete session data for JSON export (combines video, logs, network)
public struct SessionReplayData: Codable, Identifiable {
    public let sessionId: String
    public let startTime: Date
    public let endTime: Date
    public let durationMs: TimeInterval
    public let videoSegments: [String]
    public let frameCount: Int
    public let touches: [CapturedTouchEvent]
    public let logs: [LogEntry]
    public let networkRequests: [NetworkEntry]
    public let screenTransitions: [ScreenTransition]
    public let metadata: SessionMetadata

    public var id: String { sessionId }

    public init(
        sessionId: String,
        startTime: Date,
        endTime: Date,
        durationMs: TimeInterval,
        videoSegments: [String],
        frameCount: Int,
        touches: [CapturedTouchEvent],
        logs: [LogEntry],
        networkRequests: [NetworkEntry],
        screenTransitions: [ScreenTransition],
        metadata: SessionMetadata
    ) {
        self.sessionId = sessionId
        self.startTime = startTime
        self.endTime = endTime
        self.durationMs = durationMs
        self.videoSegments = videoSegments
        self.frameCount = frameCount
        self.touches = touches
        self.logs = logs
        self.networkRequests = networkRequests
        self.screenTransitions = screenTransitions
        self.metadata = metadata
    }

    /// Export as JSON data
    public func toJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Export as JSON string
    public func toJSONString() throws -> String {
        let data = try toJSON()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

/// Session log data (for JSON export)
public struct SessionLogData: Codable {
    public let sessionId: String
    public let startTime: Date
    public let endTime: Date
    public let logs: [LogEntry]
    public let networkRequests: [NetworkEntry]

    public var duration: TimeInterval {
        endTime.timeIntervalSince(startTime) * 1000
    }

    public init(
        sessionId: String,
        startTime: Date,
        endTime: Date,
        logs: [LogEntry],
        networkRequests: [NetworkEntry]
    ) {
        self.sessionId = sessionId
        self.startTime = startTime
        self.endTime = endTime
        self.logs = logs
        self.networkRequests = networkRequests
    }

    /// Export as JSON data
    public func toJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Save to file
    public func save(to url: URL) throws {
        let data = try toJSON()
        try data.write(to: url)
    }
}
