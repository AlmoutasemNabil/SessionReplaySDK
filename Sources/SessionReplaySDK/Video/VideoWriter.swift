//
//  VideoWriter.swift
//  SessionReplaySDK
//
//  Handles H.264 video encoding for session replay frames.
//  Uses AVAssetWriter for efficient video compression.
//
//  Created by AlmoutasemNabil on 2026.
//  Copyright © 2026 AlmoutasemNabil. All rights reserved.
//
//  This source code is licensed under the MIT license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

#if canImport(UIKit)
import AVFoundation
import UIKit

public final class VideoWriter {

    private let outputURL: URL
    private let size: CGSize
    private let bitrate: Int

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    private var isWriting = false
    private var frameCount: Int64 = 0
    private var lastFrameTime: CMTime = .zero

    private let writingQueue = DispatchQueue(label: "com.sessionreplay.videowriter", qos: .utility)

    private let frameRate: Int32 = 1

    public init(outputURL: URL, size: CGSize, bitrate: Int = 75_000) {
        self.outputURL = outputURL
        self.size = size
        self.bitrate = bitrate
    }

    public func startWriting() {
        writingQueue.async { [weak self] in
            self?.setupWriter()
        }
    }

    public func addFrame(_ image: UIImage) {
        writingQueue.async { [weak self] in
            self?.writeFrame(image)
        }
    }

    /// Finalizes the movie. `completion` receives `true` only when the file is
    /// actually playable.
    ///
    /// An `AVAssetWriter` writes its `moov` atom during `finishWriting()`. If
    /// that call is interrupted — most commonly because the app was suspended
    /// right after moving to the background — the writer ends in `.failed` and
    /// leaves `ftyp/wide/mdat` on disk with no index: a non-empty file that no
    /// player can open. It still invokes its completion handler, so success
    /// must be read from `status`, never assumed.
    public func finishWriting(completion: @escaping (Bool) -> Void) {
        // Deliberately captures `self` strongly. Callers release their
        // reference to the writer as soon as they stop a session, so that late
        // frames can't be appended to it. With a weak capture the writer would
        // deallocate before this block ran, AVAssetWriter.finishWriting() would
        // never be called, and the movie would be left as ftyp/wide/mdat with
        // no moov atom: a file with real bytes that no player can open.
        writingQueue.async {
            guard self.isWriting else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            // Close the input to further frames *here*, on the same serial
            // queue that writeFrame() runs on. Otherwise a frame already in
            // flight from the capture queue can be appended after
            // markAsFinished(), which puts the writer into .failed and loses
            // the moov atom — a non-empty file that will not play.
            self.isWriting = false

            self.videoInput?.markAsFinished()

            self.assetWriter?.finishWriting {

                let status = self.assetWriter?.status ?? .unknown
                let succeeded = (status == .completed)

                if succeeded {
                    print("[VideoWriter] Finished writing: \(self.outputURL.lastPathComponent)")
                    print("[VideoWriter] Total frames: \(self.frameCount)")

                    if let attributes = try? FileManager.default.attributesOfItem(atPath: self.outputURL.path),
                       let fileSize = attributes[.size] as? Int64 {
                        print("[VideoWriter] File size: \(fileSize / 1024)KB")
                    }
                } else {
                    let error = self.assetWriter?.error
                    print("[VideoWriter] FAILED to finalize \(self.outputURL.lastPathComponent) — status: \(status.rawValue), error: \(error.map(String.init(describing:)) ?? "none")")
                    print("[VideoWriter] The file has no moov atom and is not playable (frames written: \(self.frameCount))")
                }

                DispatchQueue.main.async { completion(succeeded) }
            }
        }
    }

    /// Synchronous finish writing for emergency saves (crash/terminate)
    public func finishWritingSync() {
        writingQueue.sync { [weak self] in
            guard let self = self, self.isWriting else { return }

            self.isWriting = false
            self.videoInput?.markAsFinished()

            let semaphore = DispatchSemaphore(value: 0)
            self.assetWriter?.finishWriting {
                semaphore.signal()
            }

            // Wait with timeout to avoid blocking forever
            _ = semaphore.wait(timeout: .now() + 2.0)

            if self.assetWriter?.status != .completed {
                print("[VideoWriter] FAILED to finalize \(self.outputURL.lastPathComponent) during emergency stop — not playable")
            }
        }
    }

    private func setupWriter() {
        try? FileManager.default.removeItem(at: outputURL)

        do {
            assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            print("[VideoWriter] Failed to create asset writer: \(error)")
            return
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 1,
                AVVideoExpectedSourceFrameRateKey: frameRate
            ]
        ]

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput?.expectsMediaDataInRealTime = true

        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ]

        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput!,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )

        guard let assetWriter = assetWriter,
              let videoInput = videoInput,
              assetWriter.canAdd(videoInput) else {
            print("[VideoWriter] Cannot add video input")
            return
        }

        assetWriter.add(videoInput)

        guard assetWriter.startWriting() else {
            print("[VideoWriter] Failed to start writing: \(assetWriter.error?.localizedDescription ?? "unknown")")
            return
        }

        assetWriter.startSession(atSourceTime: .zero)
        isWriting = true

        print("[VideoWriter] Started writing to: \(outputURL.lastPathComponent)")
        print("[VideoWriter] Video size: \(Int(size.width))x\(Int(size.height))")
        print("[VideoWriter] Bitrate: \(bitrate) bps")
    }

    private func writeFrame(_ image: UIImage) {
        guard isWriting,
              let assetWriter = assetWriter,
              assetWriter.status == .writing,
              let videoInput = videoInput,
              let pixelBufferAdaptor = pixelBufferAdaptor,
              videoInput.isReadyForMoreMediaData else {
            return
        }

        guard let pixelBuffer = createPixelBuffer(from: image) else {
            print("[VideoWriter] Failed to create pixel buffer")
            return
        }

        let presentationTime = CMTime(value: frameCount, timescale: frameRate)

        let success = pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime)

        if success {
            frameCount += 1
            lastFrameTime = presentationTime
        } else {
            print("[VideoWriter] Failed to append frame: \(assetWriter.error?.localizedDescription ?? "unknown")")
        }
    }

    private func createPixelBuffer(from image: UIImage) -> CVPixelBuffer? {
        guard let cgImage = image.cgImage else { return nil }

        let width = Int(size.width)
        let height = Int(size.height)

        var pixelBuffer: CVPixelBuffer?

        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            attrs as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return buffer
    }
}

// MARK: - Video Compression

public extension VideoWriter {

    static func compressVideo(
        inputURL: URL,
        outputURL: URL,
        bitrate: Int = 75_000,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        let asset = AVAsset(url: inputURL)

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetMediumQuality
        ) else {
            completion(false, NSError(domain: "VideoWriter", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to create export session"
            ]))
            return
        }

        try? FileManager.default.removeItem(at: outputURL)

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                switch exportSession.status {
                case .completed:
                    completion(true, nil)
                case .failed:
                    completion(false, exportSession.error)
                case .cancelled:
                    completion(false, NSError(domain: "VideoWriter", code: -2, userInfo: [
                        NSLocalizedDescriptionKey: "Export cancelled"
                    ]))
                default:
                    completion(false, nil)
                }
            }
        }
    }
}

#endif
