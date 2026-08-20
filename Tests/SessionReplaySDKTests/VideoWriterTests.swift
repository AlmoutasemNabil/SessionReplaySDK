//
//  VideoWriterTests.swift
//  SessionReplaySDKTests
//
//  A recorded session is worthless if the movie can't be opened. An
//  AVAssetWriter writes its `moov` atom during finishWriting(); if that is
//  interrupted the file still has bytes (ftyp/wide/mdat) but no player will
//  open it. These tests assert we produce playable files and, crucially, that
//  we report the truth when we don't.
//

#if canImport(UIKit)
import XCTest
import UIKit
import AVFoundation
@testable import SessionReplaySDK

final class VideoWriterTests: XCTestCase {

    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoWriterTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    /// Top-level atom types of an MP4, in file order.
    ///
    /// Handles the two size encodings AVAssetWriter actually emits: a 32-bit
    /// size, and the extended form where the 32-bit field is 1 and the real
    /// 64-bit size follows the type. Ignoring the extended form makes the
    /// parser stop at `mdat` and wrongly conclude a valid movie has no `moov`.
    private func atomTypes(of url: URL) throws -> [String] {
        let data = try Data(contentsOf: url)
        func integer(at index: Int, bytes: Int) -> Int {
            (0..<bytes).reduce(0) { $0 << 8 | Int(data[index + $1]) }
        }

        var types: [String] = []
        var offset = 0
        while offset + 8 <= data.count {
            var size = integer(at: offset, bytes: 4)
            let type = String(decoding: data[(offset + 4)..<(offset + 8)], as: UTF8.self)
            types.append(type)

            var headerSize = 8
            if size == 1 {                        // 64-bit extended size
                guard offset + 16 <= data.count else { break }
                size = integer(at: offset + 8, bytes: 8)
                headerSize = 16
            } else if size == 0 {                 // extends to end of file
                break
            }

            guard size >= headerSize else { break }
            offset += size
        }
        return types
    }

    private func solidImage(_ size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    func testFinishWritingProducesAPlayableFileAndReportsSuccess() throws {
        let url = directory.appendingPathComponent("ok.mp4")
        let size = CGSize(width: 320, height: 240)

        let writer = VideoWriter(outputURL: url, size: size, bitrate: 75_000)
        writer.startWriting()
        for _ in 0..<3 { writer.addFrame(solidImage(size)) }

        let done = expectation(description: "finished")
        var reported: Bool?
        writer.finishWriting { success in
            reported = success
            done.fulfill()
        }
        wait(for: [done], timeout: 30)

        XCTAssertEqual(reported, true, "A clean finish must report success")

        let types = try atomTypes(of: url)
        XCTAssertTrue(types.contains("moov"),
                      "Without a moov atom the file is not playable. Atoms: \(types)")
    }

    func testFramesArrivingDuringFinalisationDoNotCorruptTheMovie() throws {
        // Screen capture runs on its own queue, so frames can still be in
        // flight when the session is stopped. Appending one after the input is
        // marked finished fails the writer and loses the moov atom.
        let url = directory.appendingPathComponent("racy.mp4")
        let size = CGSize(width: 320, height: 240)
        let frame = solidImage(size)

        let writer = VideoWriter(outputURL: url, size: size, bitrate: 75_000)
        writer.startWriting()
        for _ in 0..<3 { writer.addFrame(frame) }

        let done = expectation(description: "finished")
        var reported: Bool?
        writer.finishWriting { success in
            reported = success
            done.fulfill()
        }
        // Late frames, exactly as the capture queue would deliver them.
        for _ in 0..<5 { writer.addFrame(frame) }

        wait(for: [done], timeout: 30)

        XCTAssertEqual(reported, true, "Late frames must not fail the writer")
        let types = try atomTypes(of: url)
        XCTAssertTrue(types.contains("moov"),
                      "Movie must still be playable despite late frames. Atoms: \(types)")
    }

    func testMovieIsFinalisedEvenWhenTheOwnerReleasesTheWriterImmediately() throws {
        // stopSession() drops its reference to the writer as soon as it asks it
        // to finish, so that in-flight frames can't be appended. Finalisation
        // must still complete: if the writer deallocates first, the file is
        // left without a moov atom and nothing can play it.
        let url = directory.appendingPathComponent("released.mp4")
        let size = CGSize(width: 320, height: 240)
        let done = expectation(description: "finished")
        var reported: Bool?

        autoreleasepool {
            var writer: VideoWriter? = VideoWriter(outputURL: url, size: size, bitrate: 75_000)
            writer?.startWriting()
            for _ in 0..<3 { writer?.addFrame(solidImage(size)) }
            writer?.finishWriting { success in
                reported = success
                done.fulfill()
            }
            writer = nil   // owner lets go straight away
        }

        wait(for: [done], timeout: 30)

        XCTAssertEqual(reported, true,
                       "Finalisation must not depend on the caller keeping the writer alive")
        let types = try atomTypes(of: url)
        XCTAssertTrue(types.contains("moov"),
                      "Movie must be playable after the owner released the writer. Atoms: \(types)")
    }

    func testFinishingAWriterThatNeverStartedReportsFailure() {
        let writer = VideoWriter(outputURL: directory.appendingPathComponent("unstarted.mp4"),
                                 size: CGSize(width: 320, height: 240))

        let done = expectation(description: "finished")
        var reported: Bool?
        writer.finishWriting { success in
            reported = success
            done.fulfill()
        }
        wait(for: [done], timeout: 30)

        XCTAssertEqual(reported, false,
                       "Nothing was written, so this must not be reported as a finished video")
    }
}
#endif
