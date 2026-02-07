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

    public func finishWriting(completion: @escaping () -> Void) {
        writingQueue.async { [weak self] in
            guard let self = self, self.isWriting else {
                DispatchQueue.main.async { completion() }
                return
            }

            self.videoInput?.markAsFinished()

            self.assetWriter?.finishWriting {
                self.isWriting = false
                print("[VideoWriter] Finished writing: \(self.outputURL.lastPathComponent)")
                print("[VideoWriter] Total frames: \(self.frameCount)")

                if let attributes = try? FileManager.default.attributesOfItem(atPath: self.outputURL.path),
                   let fileSize = attributes[.size] as? Int64 {
                    print("[VideoWriter] File size: \(fileSize / 1024)KB")
                }

                DispatchQueue.main.async { completion() }
            }
        }
    }

    /// Synchronous finish writing for emergency saves (crash/terminate)
    public func finishWritingSync() {
        writingQueue.sync { [weak self] in
            guard let self = self, self.isWriting else { return }

            self.videoInput?.markAsFinished()

            let semaphore = DispatchSemaphore(value: 0)
            self.assetWriter?.finishWriting {
                self.isWriting = false
                semaphore.signal()
            }

            // Wait with timeout to avoid blocking forever
            _ = semaphore.wait(timeout: .now() + 2.0)
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
            print("[VideoWriter] Failed to append frame: \(assetWriter?.error?.localizedDescription ?? "unknown")")
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
