//
//  NetworkInterceptor.swift
//  SessionReplaySDK
//
//  Network request interception using URLProtocol and method swizzling.
//  Captures all URLSession-based requests automatically.
//
//  Created by AlmoutasemNabil on 2026.
//  Copyright © 2026 AlmoutasemNabil. All rights reserved.
//
//  This source code is licensed under the MIT license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import ObjectiveC

// MARK: - Network Interceptor

/// Intercepts all network requests using URLProtocol registration and method swizzling
public final class NetworkInterceptor {

    public static let shared = NetworkInterceptor()

    private weak var logger: SessionLogger?
    private var isActive = false
    private let queue = DispatchQueue(label: "com.sessionreplay.network", qos: .utility)

    // Track in-flight requests for timing
    private var pendingRequests: [String: PendingRequest] = [:]

    private init() {}

    // MARK: - Lifecycle

    func startCapture(logger: SessionLogger) {
        queue.sync {
            guard !isActive else { return }
            self.logger = logger
            self.isActive = true
        }

        URLProtocol.registerClass(SessionReplayURLProtocol.self)
        URLSessionSwizzler.swizzle()
    }

    func stopCapture() {
        queue.sync {
            guard isActive else { return }
            isActive = false
            pendingRequests.removeAll()
        }

        URLProtocol.unregisterClass(SessionReplayURLProtocol.self)
        URLSessionSwizzler.unswizzle()
    }

    // MARK: - Request Tracking

    func shouldCaptureRequest(_ request: URLRequest) -> Bool {
        guard isActive else { return false }
        guard let url = request.url?.absoluteString else { return false }

        let config = logger?.currentConfig ?? SessionLoggerConfig()

        for pattern in config.excludedURLPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(url.startIndex..., in: url)
                if regex.firstMatch(in: url, options: [], range: range) != nil {
                    return false
                }
            }
        }

        return true
    }

    func recordRequestStart(_ request: URLRequest) -> String {
        let requestId = UUID().uuidString

        queue.async { [weak self] in
            self?.pendingRequests[requestId] = PendingRequest(
                request: request,
                startTime: Date(),
                timestamp: self?.logger?.getRelativeTimestamp() ?? 0
            )
        }

        return requestId
    }

    func recordRequestComplete(
        requestId: String,
        response: URLResponse?,
        data: Data?,
        error: Error?
    ) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let pending = self.pendingRequests.removeValue(forKey: requestId) else { return }
            guard let logger = self.logger else { return }

            let config = logger.currentConfig
            let httpResponse = response as? HTTPURLResponse
            let duration = Date().timeIntervalSince(pending.startTime) * 1000

            let requestHeaders = self.processHeaders(pending.request.allHTTPHeaderFields, config: config)
            let responseHeaders = self.processHeaders(httpResponse?.allHeaderFields as? [String: String], config: config)

            let requestBody = self.processBody(pending.request.httpBody, config: config)
            let responseBody = self.processBody(data, config: config)

            let entry = NetworkEntry(
                id: requestId,
                timestamp: pending.timestamp,
                absoluteTime: pending.startTime,
                method: pending.request.httpMethod ?? "GET",
                url: pending.request.url?.absoluteString ?? "",
                requestHeaders: requestHeaders,
                requestBody: requestBody?.content,
                requestBodySize: requestBody?.size,
                statusCode: httpResponse?.statusCode,
                responseHeaders: responseHeaders,
                responseBody: responseBody?.content,
                responseBodySize: responseBody?.size,
                duration: duration,
                error: error?.localizedDescription
            )

            logger.addNetworkEntry(entry)
        }
    }

    // MARK: - Helpers

    private func processHeaders(_ headers: [String: String]?, config: SessionLoggerConfig) -> [String: String]? {
        guard let headers = headers else { return nil }

        var processed: [String: String] = [:]
        for (key, value) in headers {
            if config.redactedHeaders.contains(key.lowercased()) {
                processed[key] = "[REDACTED]"
            } else {
                processed[key] = value
            }
        }
        return processed
    }

    private func processBody(_ data: Data?, config: SessionLoggerConfig) -> (content: String, size: Int)? {
        guard let data = data else { return nil }

        let size = data.count

        if size > config.maxBodySize {
            return ("[TRUNCATED: \(size) bytes]", size)
        }

        if let string = String(data: data, encoding: .utf8) {
            return (string, size)
        }

        return (data.base64EncodedString(), size)
    }
}

// MARK: - Pending Request

private struct PendingRequest {
    let request: URLRequest
    let startTime: Date
    let timestamp: TimeInterval
}

// MARK: - URLProtocol Interceptor

/// Custom URLProtocol that intercepts and captures network requests
final class SessionReplayURLProtocol: URLProtocol {

    private static let handledKey = "SessionReplayURLProtocol_Handled"

    private var dataTask: URLSessionDataTask?
    private var requestId: String?
    private var responseData = Data()
    private var capturedResponse: URLResponse?

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.protocolClasses = []
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    // MARK: - URLProtocol Overrides

    override class func canInit(with request: URLRequest) -> Bool {
        if URLProtocol.property(forKey: handledKey, in: request) != nil {
            return false
        }

        guard let scheme = request.url?.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        return NetworkInterceptor.shared.shouldCaptureRequest(request)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let mutableRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "SessionReplay", code: -1))
            return
        }

        URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutableRequest)

        requestId = NetworkInterceptor.shared.recordRequestStart(request)

        dataTask = session.dataTask(with: mutableRequest as URLRequest)
        dataTask?.resume()
    }

    override func stopLoading() {
        dataTask?.cancel()
    }
}

// MARK: - URLSessionDataDelegate

extension SessionReplayURLProtocol: URLSessionDataDelegate {

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        capturedResponse = response
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        responseData.append(data)
        client?.urlProtocol(self, didLoad: data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let requestId = requestId {
            NetworkInterceptor.shared.recordRequestComplete(
                requestId: requestId,
                response: capturedResponse,
                data: responseData.isEmpty ? nil : responseData,
                error: error
            )
        }

        if let error = error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}

// MARK: - URLSession Method Swizzling

/// Swizzles URLSession methods to capture requests from sessions with custom configurations
final class URLSessionSwizzler {

    private static var isSwizzled = false
    private static let lock = NSLock()

    static func swizzle() {
        lock.lock()
        defer { lock.unlock() }

        guard !isSwizzled else { return }
        isSwizzled = true

        swizzleDataTaskWithRequest()
        swizzleDataTaskWithURL()
    }

    static func unswizzle() {
        lock.lock()
        defer { lock.unlock() }

        guard isSwizzled else { return }
        isSwizzled = false

        swizzleDataTaskWithRequest()
        swizzleDataTaskWithURL()
    }

    // MARK: - Swizzle Implementations

    private static func swizzleDataTaskWithRequest() {
        let originalSelector = #selector(URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URLRequest, @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask)
        let swizzledSelector = #selector(URLSession.sr_dataTask(with:completionHandler:))

        guard let originalMethod = class_getInstanceMethod(URLSession.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(URLSession.self, swizzledSelector) else {
            return
        }

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }

    private static func swizzleDataTaskWithURL() {
        let originalSelector = #selector(URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URL, @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask)
        let swizzledSelector = #selector(URLSession.sr_dataTask(withURL:completionHandler:))

        guard let originalMethod = class_getInstanceMethod(URLSession.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(URLSession.self, swizzledSelector) else {
            return
        }

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
}

// MARK: - URLSession Extension for Swizzling

extension URLSession {

    @objc func sr_dataTask(
        with request: URLRequest,
        completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTask {

        guard NetworkInterceptor.shared.shouldCaptureRequest(request) else {
            return sr_dataTask(with: request, completionHandler: completionHandler)
        }

        let requestId = NetworkInterceptor.shared.recordRequestStart(request)

        let wrappedHandler: (Data?, URLResponse?, Error?) -> Void = { data, response, error in
            NetworkInterceptor.shared.recordRequestComplete(
                requestId: requestId,
                response: response,
                data: data,
                error: error
            )
            completionHandler(data, response, error)
        }

        return sr_dataTask(with: request, completionHandler: wrappedHandler)
    }

    @objc func sr_dataTask(
        withURL url: URL,
        completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTask {

        let request = URLRequest(url: url)

        guard NetworkInterceptor.shared.shouldCaptureRequest(request) else {
            return sr_dataTask(withURL: url, completionHandler: completionHandler)
        }

        let requestId = NetworkInterceptor.shared.recordRequestStart(request)

        let wrappedHandler: (Data?, URLResponse?, Error?) -> Void = { data, response, error in
            NetworkInterceptor.shared.recordRequestComplete(
                requestId: requestId,
                response: response,
                data: data,
                error: error
            )
            completionHandler(data, response, error)
        }

        return sr_dataTask(withURL: url, completionHandler: wrappedHandler)
    }
}
