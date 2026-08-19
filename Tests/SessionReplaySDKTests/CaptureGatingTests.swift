//
//  CaptureGatingTests.swift
//  SessionReplaySDKTests
//
//  Two guarantees:
//  1. Nothing is captured while no session is recording. The SDK is configured
//     at launch in host apps but may never record (remote flag off), and it must
//     cost nothing and collect nothing in that state.
//  2. Credentials never reach the captured log.
//

import XCTest
@testable import SessionReplaySDK

final class CaptureGatingTests: XCTestCase {

    // MARK: - Nothing runs without a session

    func testNetworkInterceptorIsNotCapturingWithoutASession() {
        XCTAssertFalse(SessionReplayManager.shared.isRecording,
                       "Tests assume no session is running")
        XCTAssertFalse(NetworkInterceptor.shared.isCapturing)
    }

    func testRequestsAreNotCapturedWhileInactive() {
        let request = URLRequest(url: URL(string: "https://api.example.com/orders")!)

        XCTAssertFalse(NetworkInterceptor.shared.shouldCaptureRequest(request),
                       "No session is recording, so nothing should be captured")
    }

    func testResponseBodiesAreNotBufferedWhileInactive() {
        // The completion-handler swizzles stay installed for the process lifetime
        // once any session has run, so the buffering hook must gate on isCapturing.
        let task = URLSession.shared.dataTask(with: URL(string: "https://api.example.com/x")!)

        task.sr_appendData(Data(repeating: 0xAB, count: 1024))

        XCTAssertNil(task.sr_accumulatedData,
                     "Response bodies must not accumulate when no session is recording")
    }

    // MARK: - Redaction

    private func makeConfig(redacting headers: Set<String>) -> SessionLoggerConfig {
        var config = SessionLoggerConfig()
        config.redactedHeaders = headers
        return config
    }

    func testDefaultSensitiveHeadersAreRedacted() {
        let config = SessionLoggerConfig()
        let processed = NetworkInterceptor.shared.processHeaders(
            [
                "Authorization": "Bearer super-secret",
                "Cookie": "session=abc123",
                "X-API-Key": "key-live-1234",
                "Content-Type": "application/json"
            ],
            config: config
        )

        XCTAssertEqual(processed?["Authorization"], "[REDACTED]")
        XCTAssertEqual(processed?["Cookie"], "[REDACTED]")
        XCTAssertEqual(processed?["X-API-Key"], "[REDACTED]")
        XCTAssertEqual(processed?["Content-Type"], "application/json",
                       "Non-sensitive headers must survive")
    }

    func testRedactionIsCaseInsensitiveOnBothSides() {
        // The config is documented as case-insensitive; an integrator passing
        // "Authorization" must still redact a lowercase header and vice versa.
        let processed = NetworkInterceptor.shared.processHeaders(
            ["authorization": "Bearer secret", "X-Auth-Token": "t0ken"],
            config: makeConfig(redacting: ["Authorization", "x-auth-TOKEN"])
        )

        XCTAssertEqual(processed?["authorization"], "[REDACTED]")
        XCTAssertEqual(processed?["X-Auth-Token"], "[REDACTED]")
    }

    func testNoHeadersProducesNil() {
        XCTAssertNil(NetworkInterceptor.shared.processHeaders(nil, config: SessionLoggerConfig()))
    }

    // MARK: - Body handling

    func testOversizedBodiesAreTruncatedRatherThanCaptured() {
        var config = SessionLoggerConfig()
        config.maxBodySize = 16

        let result = NetworkInterceptor.shared.processBody(
            Data(repeating: 0x41, count: 1024), config: config
        )

        XCTAssertEqual(result?.size, 1024)
        XCTAssertEqual(result?.content, "[TRUNCATED: 1024 bytes]")
        XCTAssertFalse(result?.content.contains("AAAA") ?? true,
                       "Truncated bodies must not leak their contents")
    }

    func testSmallTextBodyIsCapturedVerbatim() {
        let result = NetworkInterceptor.shared.processBody(
            Data(#"{"ok":true}"#.utf8), config: SessionLoggerConfig()
        )

        XCTAssertEqual(result?.content, #"{"ok":true}"#)
        XCTAssertEqual(result?.size, 11)
    }

    func testBinaryBodyIsBase64Encoded() {
        let bytes = Data([0xFF, 0xFE, 0xFD])
        let result = NetworkInterceptor.shared.processBody(bytes, config: SessionLoggerConfig())

        XCTAssertEqual(result?.content, bytes.base64EncodedString())
    }

    func testNilBodyProducesNil() {
        XCTAssertNil(NetworkInterceptor.shared.processBody(nil, config: SessionLoggerConfig()))
    }
}
