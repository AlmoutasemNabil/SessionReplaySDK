//
//  SessionUploader.swift
//  SessionReplaySDK
//
//  Handles uploading session recordings (video + JSON metadata) to a backend.
//  Supports custom upload endpoints, progress tracking, and retry logic.
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

// MARK: - Upload Configuration

/// Configuration for session uploads
public struct SessionUploadConfig {
    /// Base URL for the upload endpoint
    public var baseURL: URL

    /// API key or auth token for authentication
    public var apiKey: String?

    /// Custom headers to include with requests
    public var additionalHeaders: [String: String] = [:]

    /// Maximum number of retry attempts
    public var maxRetries: Int = 3

    /// Timeout interval for uploads (in seconds)
    public var timeoutInterval: TimeInterval = 120

    /// Whether to compress video before upload
    public var compressBeforeUpload: Bool = true

    /// Whether to delete local files after successful upload
    public var deleteAfterUpload: Bool = false

    /// Chunk size for large file uploads (in bytes, 0 = no chunking)
    public var chunkSize: Int = 0

    public init(baseURL: URL, apiKey: String? = nil) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }
}

// MARK: - Upload Delegate

/// Delegate protocol for upload events
public protocol SessionUploadDelegate: AnyObject {
    /// Called when upload starts
    func uploadDidStart(sessionId: String)

    /// Called with upload progress
    func uploadProgress(sessionId: String, progress: Double)

    /// Called when upload completes successfully
    func uploadDidComplete(sessionId: String, response: SessionUploadResponse)

    /// Called when upload fails
    func uploadDidFail(sessionId: String, error: Error)
}

// Default implementations
public extension SessionUploadDelegate {
    func uploadDidStart(sessionId: String) {}
    func uploadProgress(sessionId: String, progress: Double) {}
    func uploadDidComplete(sessionId: String, response: SessionUploadResponse) {}
    func uploadDidFail(sessionId: String, error: Error) {}
}

// MARK: - Upload Response

/// Response from a successful upload
public struct SessionUploadResponse: Codable {
    public let sessionId: String
    public let videoURL: String?
    public let metadataURL: String?
    public let message: String?
    public let timestamp: Date?

    public init(sessionId: String, videoURL: String? = nil, metadataURL: String? = nil, message: String? = nil, timestamp: Date? = nil) {
        self.sessionId = sessionId
        self.videoURL = videoURL
        self.metadataURL = metadataURL
        self.message = message
        self.timestamp = timestamp
    }
}

// MARK: - Upload Error

/// Errors that can occur during upload
public enum SessionUploadError: LocalizedError {
    case notConfigured
    case sessionNotFound
    case videoFileNotFound
    case metadataFileNotFound
    case networkError(Error)
    case serverError(statusCode: Int, message: String?)
    case invalidResponse
    case uploadCancelled
    case maxRetriesExceeded

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Upload service is not configured. Call configure() first."
        case .sessionNotFound:
            return "Session not found"
        case .videoFileNotFound:
            return "Video file not found"
        case .metadataFileNotFound:
            return "Metadata file not found"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message ?? "Unknown error")"
        case .invalidResponse:
            return "Invalid response from server"
        case .uploadCancelled:
            return "Upload was cancelled"
        case .maxRetriesExceeded:
            return "Maximum retry attempts exceeded"
        }
    }
}

// MARK: - Upload Status

/// Status of an upload operation
public enum SessionUploadStatus {
    case pending
    case uploading(progress: Double)
    case completed(response: SessionUploadResponse)
    case failed(error: Error)
    case cancelled
}

// MARK: - Session Uploader

/// Main class for uploading session recordings to a backend
public final class SessionUploader {

    public static let shared = SessionUploader()

    // MARK: - Properties

    private var config: SessionUploadConfig?
    private let uploadQueue = DispatchQueue(label: "com.sessionreplay.upload", qos: .utility)
    private var activeTasks: [String: URLSessionTask] = [:]
    private var uploadStatuses: [String: SessionUploadStatus] = [:]

    public weak var delegate: SessionUploadDelegate?

    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = self.config?.timeoutInterval ?? 120
        config.timeoutIntervalForResource = self.config?.timeoutInterval ?? 120
        return URLSession(configuration: config, delegate: nil, delegateQueue: nil)
    }()

    private init() {}

    // MARK: - Configuration

    /// Configure the uploader with endpoint and authentication
    public func configure(_ config: SessionUploadConfig) {
        self.config = config
    }

    /// Check if uploader is configured
    public var isConfigured: Bool {
        config != nil
    }

    // MARK: - Upload Methods

    /// Upload a session by ID
    /// - Parameters:
    ///   - sessionId: The session ID to upload
    ///   - completion: Completion handler with result
    public func uploadSession(
        sessionId: String,
        completion: @escaping (Result<SessionUploadResponse, Error>) -> Void
    ) {
        guard let config = config else {
            completion(.failure(SessionUploadError.notConfigured))
            return
        }

        #if canImport(UIKit)
        let manager = SessionReplayManager.shared
        let sessions = manager.getSavedSessions()

        guard let session = sessions.first(where: { $0.sessionId == sessionId }) else {
            completion(.failure(SessionUploadError.sessionNotFound))
            return
        }

        uploadSession(session, completion: completion)
        #else
        completion(.failure(SessionUploadError.notConfigured))
        #endif
    }

    #if canImport(UIKit)
    /// Upload a session object
    /// - Parameters:
    ///   - session: The SessionReplayData to upload
    ///   - completion: Completion handler with result
    public func uploadSession(
        _ session: SessionReplayData,
        completion: @escaping (Result<SessionUploadResponse, Error>) -> Void
    ) {
        guard let config = config else {
            completion(.failure(SessionUploadError.notConfigured))
            return
        }

        let manager = SessionReplayManager.shared

        guard let videoURL = manager.getVideoURL(for: session) else {
            completion(.failure(SessionUploadError.videoFileNotFound))
            return
        }

        guard let jsonURL = manager.getJSONURL(for: session) else {
            completion(.failure(SessionUploadError.metadataFileNotFound))
            return
        }

        uploadQueue.async { [weak self] in
            self?.performUpload(
                sessionId: session.sessionId,
                videoURL: videoURL,
                jsonURL: jsonURL,
                config: config,
                completion: completion
            )
        }
    }
    #endif

    /// Upload video and JSON files directly
    /// - Parameters:
    ///   - sessionId: Session identifier
    ///   - videoURL: Local URL of the video file
    ///   - jsonURL: Local URL of the JSON metadata file
    ///   - completion: Completion handler with result
    public func uploadFiles(
        sessionId: String,
        videoURL: URL,
        jsonURL: URL,
        completion: @escaping (Result<SessionUploadResponse, Error>) -> Void
    ) {
        guard let config = config else {
            completion(.failure(SessionUploadError.notConfigured))
            return
        }

        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            completion(.failure(SessionUploadError.videoFileNotFound))
            return
        }

        guard FileManager.default.fileExists(atPath: jsonURL.path) else {
            completion(.failure(SessionUploadError.metadataFileNotFound))
            return
        }

        uploadQueue.async { [weak self] in
            self?.performUpload(
                sessionId: sessionId,
                videoURL: videoURL,
                jsonURL: jsonURL,
                config: config,
                completion: completion
            )
        }
    }

    /// Cancel an ongoing upload
    public func cancelUpload(sessionId: String) {
        uploadQueue.async { [weak self] in
            if let task = self?.activeTasks[sessionId] {
                task.cancel()
                self?.activeTasks.removeValue(forKey: sessionId)
                self?.uploadStatuses[sessionId] = .cancelled
            }
        }
    }

    /// Get the status of an upload
    public func getUploadStatus(sessionId: String) -> SessionUploadStatus? {
        return uploadStatuses[sessionId]
    }

    // MARK: - Private Upload Implementation

    private func performUpload(
        sessionId: String,
        videoURL: URL,
        jsonURL: URL,
        config: SessionUploadConfig,
        retryCount: Int = 0,
        completion: @escaping (Result<SessionUploadResponse, Error>) -> Void
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.uploadDidStart(sessionId: sessionId)
        }

        uploadStatuses[sessionId] = .uploading(progress: 0)

        // Create multipart form data
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: config.baseURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Add authentication
        if let apiKey = config.apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        // Add custom headers
        for (key, value) in config.additionalHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Build multipart body
        var body = Data()

        // Add session ID
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"sessionId\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(sessionId)\r\n".data(using: .utf8)!)

        // Add video file
        if let videoData = try? Data(contentsOf: videoURL) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"video\"; filename=\"\(videoURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: video/mp4\r\n\r\n".data(using: .utf8)!)
            body.append(videoData)
            body.append("\r\n".data(using: .utf8)!)
        }

        // Add JSON metadata
        if let jsonData = try? Data(contentsOf: jsonURL) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"metadata\"; filename=\"\(jsonURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
            body.append(jsonData)
            body.append("\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body
        request.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")

        // Create upload task
        let task = urlSession.dataTask(with: request) { [weak self] data, response, error in
            self?.activeTasks.removeValue(forKey: sessionId)

            if let error = error {
                // Check if cancelled
                if (error as NSError).code == NSURLErrorCancelled {
                    self?.uploadStatuses[sessionId] = .cancelled
                    DispatchQueue.main.async {
                        completion(.failure(SessionUploadError.uploadCancelled))
                    }
                    return
                }

                // Retry logic
                if retryCount < config.maxRetries {
                    self?.performUpload(
                        sessionId: sessionId,
                        videoURL: videoURL,
                        jsonURL: jsonURL,
                        config: config,
                        retryCount: retryCount + 1,
                        completion: completion
                    )
                    return
                }

                self?.uploadStatuses[sessionId] = .failed(error: error)
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.uploadDidFail(sessionId: sessionId, error: SessionUploadError.networkError(error))
                    completion(.failure(SessionUploadError.networkError(error)))
                }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self?.uploadStatuses[sessionId] = .failed(error: SessionUploadError.invalidResponse)
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.uploadDidFail(sessionId: sessionId, error: SessionUploadError.invalidResponse)
                    completion(.failure(SessionUploadError.invalidResponse))
                }
                return
            }

            // Check status code
            guard (200...299).contains(httpResponse.statusCode) else {
                let message = data.flatMap { String(data: $0, encoding: .utf8) }
                let error = SessionUploadError.serverError(statusCode: httpResponse.statusCode, message: message)
                self?.uploadStatuses[sessionId] = .failed(error: error)
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.uploadDidFail(sessionId: sessionId, error: error)
                    completion(.failure(error))
                }
                return
            }

            // Parse response
            var uploadResponse = SessionUploadResponse(sessionId: sessionId, timestamp: Date())

            if let data = data {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let parsed = try? decoder.decode(SessionUploadResponse.self, from: data) {
                    uploadResponse = parsed
                }
            }

            self?.uploadStatuses[sessionId] = .completed(response: uploadResponse)

            // Delete local files if configured
            if config.deleteAfterUpload {
                try? FileManager.default.removeItem(at: videoURL)
                try? FileManager.default.removeItem(at: jsonURL)
            }

            DispatchQueue.main.async { [weak self] in
                self?.delegate?.uploadDidComplete(sessionId: sessionId, response: uploadResponse)
                completion(.success(uploadResponse))
            }
        }

        activeTasks[sessionId] = task
        task.resume()
    }

    // MARK: - Batch Upload

    /// Upload all pending sessions
    public func uploadAllPendingSessions(
        completion: @escaping ([(String, Result<SessionUploadResponse, Error>)]) -> Void
    ) {
        #if canImport(UIKit)
        let sessions = SessionReplayManager.shared.getSavedSessions()
        var results: [(String, Result<SessionUploadResponse, Error>)] = []
        let group = DispatchGroup()

        for session in sessions {
            group.enter()
            uploadSession(session) { result in
                results.append((session.sessionId, result))
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(results)
        }
        #else
        completion([])
        #endif
    }
}

// MARK: - Convenience Extensions

#if canImport(UIKit)
public extension SessionReplayManager {

    /// Upload the current session (after stopping)
    /// Note: The session must be stopped and saved before uploading
    func uploadCurrentSession(
        completion: @escaping (Result<SessionUploadResponse, Error>) -> Void
    ) {
        guard let session = currentSession else {
            completion(.failure(SessionUploadError.sessionNotFound))
            return
        }

        // Use session ID to find the saved SessionReplayData
        SessionUploader.shared.uploadSession(sessionId: session.sessionId, completion: completion)
    }

    /// Upload a specific session by ID
    func uploadSession(
        sessionId: String,
        completion: @escaping (Result<SessionUploadResponse, Error>) -> Void
    ) {
        SessionUploader.shared.uploadSession(sessionId: sessionId, completion: completion)
    }
}
#endif
