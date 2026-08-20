//
//  SessionRotationTests.swift
//  SessionReplaySDKTests
//
//  Host apps rotate sessions: stop one, upload it, start the next. Cashier does
//  this on every interval boundary. These tests cover what happens when a new
//  session starts while the previous one is still being finalised, which
//  produced sessions on disk whose logs belonged to a different session, and
//  live recordings whose video file was deleted mid-write.
//

#if canImport(UIKit)
import XCTest
import UIKit
@testable import SessionReplaySDK

final class SessionRotationTests: XCTestCase {

    private var manager: SessionReplayManager { .shared }
    private var storage: URL!

    override func setUp() {
        super.setUp()
        storage = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionRotationTests-\(UUID().uuidString)", isDirectory: true)

        var config = SessionReplayConfig()
        config.storageDirectory = storage
        config.autoStartOnLaunch = false
        config.enableCrashRecovery = false
        config.captureTouches = false
        // Logs-only keeps the test off AVFoundation while exercising the same
        // save path; the video path is covered by the ownership assertions below.
        config.enableVideoRecording = false
        config.debugLogging = false
        manager.configure(config)
    }

    override func tearDown() {
        if manager.isRecording { manager.stopSession() }
        try? FileManager.default.removeItem(at: storage)
        super.tearDown()
    }

    private func savedSessionFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: storage, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" } ?? []
    }

    private func decode(_ url: URL) throws -> SessionReplayData {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SessionReplayData.self, from: Data(contentsOf: url))
    }

    // MARK: - A stopped session keeps its own identity

    func testStoppingThenImmediatelyStartingKeepsEachSessionsOwnIdentity() throws {
        manager.startSession()
        let first = try XCTUnwrap(manager.currentSession?.sessionId)

        // Rotation: stop without waiting, start the next one straight away.
        manager.stopSession()
        manager.startSession()
        let second = try XCTUnwrap(manager.currentSession?.sessionId)
        XCTAssertNotEqual(first, second)

        let files = savedSessionFiles()
        XCTAssertEqual(files.count, 1, "Exactly the stopped session should have been saved")

        let saved = try decode(try XCTUnwrap(files.first))
        XCTAssertEqual(saved.sessionId, first,
                       "The saved session must be the one that was stopped, not the one that just started")
        XCTAssertNotEqual(saved.sessionId, second)
    }

    func testStoppingClearsTheCurrentSession() {
        manager.startSession()
        XCTAssertNotNil(manager.currentSession)

        manager.stopSession()

        XCTAssertFalse(manager.isRecording)
        XCTAssertNil(manager.currentSession,
                     "A stopped session must not remain current, or the next save can inherit it")
    }

    func testSavedSessionCarriesItsOwnStartTime() throws {
        manager.startSession()
        let started = try XCTUnwrap(manager.currentSession?.startTime)
        manager.stopSession()
        manager.startSession()   // rotation

        let saved = try decode(try XCTUnwrap(savedSessionFiles().first))
        XCTAssertEqual(saved.startTime.timeIntervalSince1970,
                       started.timeIntervalSince1970,
                       accuracy: 1.0,   // startTime is encoded as ISO8601 (whole seconds)
                       "A session's start time must not be replaced by the next session's")
        XCTAssertGreaterThanOrEqual(saved.endTime, saved.startTime)
    }

    // MARK: - The async video-finalisation window

    func testSavedSessionIsTheStoppedOneWhenRotationHappensDuringVideoFinalisation() throws {
        // Video on: finishWriting() completes asynchronously, which is the
        // window a host app's stop -> start rotation lands in.
        var config = SessionReplayConfig()
        config.storageDirectory = storage
        config.autoStartOnLaunch = false
        config.enableCrashRecovery = false
        config.captureTouches = false
        config.enableVideoRecording = true
        config.debugLogging = false
        manager.configure(config)

        manager.startSession()
        let first = try XCTUnwrap(manager.currentSession?.sessionId)

        let firstSaved = expectation(description: "first session saved")
        manager.stopSession { firstSaved.fulfill() }

        // The host rotates straight away without awaiting the completion —
        // exactly what happens at an interval boundary.
        manager.startSession()
        let second = try XCTUnwrap(manager.currentSession?.sessionId)
        XCTAssertNotEqual(first, second)

        wait(for: [firstSaved], timeout: 30)

        let files = savedSessionFiles()
        XCTAssertEqual(files.count, 1, "Only the stopped session should be on disk")

        let saved = try decode(try XCTUnwrap(files.first))
        XCTAssertEqual(saved.sessionId, first,
                       "The completion must save the session it stopped, not the one that started meanwhile")
        XCTAssertTrue(saved.videoSegments.allSatisfy { $0.contains(first) },
                      "Video segments must belong to the saved session, not the live one")

        let secondSaved = expectation(description: "second session saved")
        manager.stopSession { secondSaved.fulfill() }
        wait(for: [secondSaved], timeout: 30)
    }

    // MARK: - The live session is not listed or deletable

    func testActiveSessionIsNotListedAsSaved() {
        manager.startSession()
        let active = manager.currentSession?.sessionId

        let listed = manager.getSavedSessions().map(\.sessionId)

        XCTAssertFalse(listed.contains(where: { $0 == active }),
                       "An in-progress session must not be offered for upload or deletion")
    }

    func testDeletingTheActiveSessionIsRefused() throws {
        manager.startSession()
        let activeId = try XCTUnwrap(manager.currentSession?.sessionId)
        let segment = "\(activeId)_segment0.mp4"

        // Stand in for the live recording's video file.
        let videoURL = storage.appendingPathComponent(segment)
        FileManager.default.createFile(atPath: videoURL.path, contents: Data([0x00]))

        let live = SessionReplayData(
            sessionId: activeId,
            startTime: Date(),
            endTime: Date(),
            durationMs: 0,
            videoSegments: [segment],
            frameCount: 0,
            touches: [],
            logs: [],
            networkRequests: [],
            screenTransitions: [],
            metadata: SessionMetadata(
                appVersion: "test", buildNumber: "1", osVersion: "test",
                deviceModel: "test", deviceId: nil, locale: "en_US", timezone: "UTC"
            ),
            userInfo: nil
        )

        manager.deleteSession(live)

        XCTAssertTrue(FileManager.default.fileExists(atPath: videoURL.path),
                      "Deleting the recording session must not unlink the video being written")
    }

    func testDeletingAFinishedSessionStillWorks() throws {
        manager.startSession()
        manager.stopSession()

        let saved = try XCTUnwrap(manager.getSavedSessions().first)
        let jsonURL = storage.appendingPathComponent("\(saved.sessionId).json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonURL.path))

        manager.deleteSession(saved)

        XCTAssertFalse(FileManager.default.fileExists(atPath: jsonURL.path),
                       "Finished sessions must still be deletable")
    }
}
#endif
