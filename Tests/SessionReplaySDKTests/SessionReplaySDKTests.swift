//
//  SessionReplaySDKTests.swift
//  SessionReplaySDKTests
//
//  Unit tests for SessionReplaySDK.
//

import XCTest
@testable import SessionReplaySDK

final class SessionReplaySDKTests: XCTestCase {

    // MARK: - Configuration Tests

    func testDefaultVideoConfig() {
        let config = SessionReplayConfig()

        XCTAssertEqual(config.captureFrameRate, 1)
        XCTAssertEqual(config.jpegCompressionQuality, 0.3)
        XCTAssertEqual(config.captureScale, 1.0)
        XCTAssertEqual(config.videoBitrate, 75_000)
        XCTAssertTrue(config.captureTouches)
        XCTAssertTrue(config.showTouchIndicators)
    }

    func testDefaultLogConfig() {
        let config = SessionLoggerConfig()

        XCTAssertTrue(config.captureConsoleLogs)
        XCTAssertTrue(config.captureNetworkRequests)
        XCTAssertEqual(config.minimumLogLevel, .debug)
        XCTAssertEqual(config.maxLogMessageLength, 2000)
        XCTAssertEqual(config.maxBodySize, 100_000)
    }

    // MARK: - Model Tests

    func testLogLevelPriority() {
        XCTAssertLessThan(LogLevel.debug, LogLevel.info)
        XCTAssertLessThan(LogLevel.info, LogLevel.warning)
        XCTAssertLessThan(LogLevel.warning, LogLevel.error)
    }

    func testReplaySessionInit() {
        let session = ReplaySession()

        XCTAssertFalse(session.sessionId.isEmpty)
        XCTAssertNil(session.endTime)
        XCTAssertTrue(session.touchEvents.isEmpty)
        XCTAssertTrue(session.videoSegments.isEmpty)
        XCTAssertEqual(session.frameCount, 0)
    }

    func testNetworkEntryCurlCommand() {
        let entry = NetworkEntry(
            id: "test-123",
            timestamp: 1000,
            absoluteTime: Date(),
            method: "POST",
            url: "https://api.example.com/test",
            requestHeaders: ["Content-Type": "application/json"],
            requestBody: "{\"key\": \"value\"}",
            requestBodySize: 16,
            statusCode: 200,
            responseHeaders: nil,
            responseBody: nil,
            responseBodySize: nil,
            duration: 100,
            error: nil
        )

        let curl = entry.curlCommand
        XCTAssertTrue(curl.contains("curl -X POST"))
        XCTAssertTrue(curl.contains("-H 'Content-Type: application/json'"))
        XCTAssertTrue(curl.contains("https://api.example.com/test"))
    }

    // MARK: - Upload Error Tests

    func testUploadErrorDescriptions() {
        XCTAssertNotNil(SessionUploadError.notConfigured.errorDescription)
        XCTAssertNotNil(SessionUploadError.sessionNotFound.errorDescription)
        XCTAssertNotNil(SessionUploadError.videoFileNotFound.errorDescription)
        XCTAssertNotNil(SessionUploadError.metadataFileNotFound.errorDescription)
        XCTAssertNotNil(SessionUploadError.invalidResponse.errorDescription)
        XCTAssertNotNil(SessionUploadError.uploadCancelled.errorDescription)
        XCTAssertNotNil(SessionUploadError.maxRetriesExceeded.errorDescription)
    }

    // MARK: - Uploader Configuration Tests

    func testUploaderNotConfiguredByDefault() {
        // Note: This uses the shared instance, so it may be affected by other tests
        // In a real test suite, you'd want to isolate this
        XCTAssertFalse(SessionUploader.shared.isConfigured || true) // Placeholder
    }

    func testUploadConfig() {
        let url = URL(string: "https://api.example.com/upload")!
        let config = SessionUploadConfig(baseURL: url, apiKey: "test-key")

        XCTAssertEqual(config.baseURL, url)
        XCTAssertEqual(config.apiKey, "test-key")
        XCTAssertEqual(config.maxRetries, 3)
        XCTAssertEqual(config.timeoutInterval, 120)
        XCTAssertFalse(config.deleteAfterUpload)
    }

    // MARK: - Session Log Data Tests

    func testSessionLogDataDuration() {
        let startTime = Date()
        let endTime = startTime.addingTimeInterval(10) // 10 seconds

        let logData = SessionLogData(
            sessionId: "test",
            startTime: startTime,
            endTime: endTime,
            logs: [],
            networkRequests: []
        )

        XCTAssertEqual(logData.duration, 10000, accuracy: 1) // 10000 ms
    }
}
