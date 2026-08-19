//
//  NetworkInterceptor.swift
//  SessionReplaySDK
//
//  Network request interception using URLSession method swizzling.
//  Captures ALL URLSession-based requests including those from custom sessions
//  with SSL pinning (e.g., Alamofire with ServerTrustManager, FNetwork, etc).
//
//  This implementation is inspired by OpenTelemetry-Swift and Atlantis approaches:
//  - Swizzles URLSessionTask.resume to capture ALL requests at the point they start
//  - Uses objc_setAssociatedObject to attach metadata to tasks
//  - Uses KVO on task.state to capture completion for delegate-based tasks
//  - Wraps completion handlers for completion-based tasks
//
//  Created by AlmoutasemNabil on 2026.
//  Copyright © 2026 AlmoutasemNabil. All rights reserved.
//
//  This source code is licensed under the MIT license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import ObjectiveC

// MARK: - Associated Object Keys

private var taskIdKey: UInt8 = 0
private var taskStartTimeKey: UInt8 = 1
private var taskRequestKey: UInt8 = 2
private var taskResponseDataKey: UInt8 = 3
private var originalDelegateKey: UInt8 = 4
private var hasInjectedDelegateKey: UInt8 = 5
private var taskObserverKey: UInt8 = 6
private var taskCompletedKey: UInt8 = 7

// MARK: - Network Interceptor

/// Intercepts all network requests using URLSession method swizzling.
/// Works with ALL URLSession configurations including custom sessions with SSL pinning.
public final class NetworkInterceptor {

    public static let shared = NetworkInterceptor()

    private weak var logger: SessionLogger?
    private var isActive = false
    private let queue = DispatchQueue(label: "com.sessionreplay.network", qos: .utility)

    private init() {}

    // MARK: - Lifecycle

    func startCapture(logger: SessionLogger) {
        queue.sync {
            guard !isActive else { return }
            self.logger = logger
            self.isActive = true
        }

        // Swizzle URLSession methods - this works with ALL URLSession instances
        URLSessionSwizzler.swizzleIfNeeded()

        print("[SessionReplay] Network capture started (comprehensive URLSession swizzling)")
    }

    func stopCapture() {
        queue.sync {
            guard isActive else { return }
            isActive = false
        }

        print("[SessionReplay] Network capture stopped")
    }

    /// Whether a session is currently capturing network traffic. The URLSession
    /// swizzles stay installed for the process lifetime once a session has run,
    /// so every hook checks this before doing any work.
    var isCapturing: Bool {
        queue.sync { isActive }
    }

    // MARK: - Request Tracking

    func shouldCaptureRequest(_ request: URLRequest?) -> Bool {
        guard isActive else { return false }
        guard let url = request?.url?.absoluteString else { return false }

        let config = logger?.currentConfig ?? SessionLoggerConfig()

        // Check excluded URL patterns
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

    /// Called when a task is about to resume (start)
    func taskWillResume(_ task: URLSessionTask) {
        guard isActive else { return }
        guard let request = task.originalRequest ?? task.currentRequest else { return }
        guard shouldCaptureRequest(request) else { return }

        // Check if already tracking this task (avoid double-tracking on retry)
        if objc_getAssociatedObject(task, &taskIdKey) != nil { return }

        // Generate unique ID and attach to task
        let taskId = UUID().uuidString
        let startTime = Date()
        let timestamp = logger?.getRelativeTimestamp() ?? 0

        objc_setAssociatedObject(task, &taskIdKey, taskId, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(task, &taskStartTimeKey, startTime, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(task, &taskRequestKey, request, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        // Store timestamp in a wrapper since TimeInterval is not an object
        let timestampWrapper = TimestampWrapper(timestamp: timestamp)
        objc_setAssociatedObject(task, &taskResponseDataKey, timestampWrapper, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        // Add KVO observer for task state to capture completion for delegate-based tasks
        let observer = TaskStateObserver(task: task, interceptor: self)
        objc_setAssociatedObject(task, &taskObserverKey, observer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        print("[SessionReplay] Task started: \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "")")
    }

    /// Called when a task completes
    func taskDidComplete(_ task: URLSessionTask, error: Error?) {
        guard isActive else { return }

        // Check if already completed (avoid duplicate logging)
        let alreadyCompleted = objc_getAssociatedObject(task, &taskCompletedKey) as? Bool ?? false
        if !alreadyCompleted {
            objc_setAssociatedObject(task, &taskCompletedKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }

        guard let taskId = objc_getAssociatedObject(task, &taskIdKey) as? String,
              let startTime = objc_getAssociatedObject(task, &taskStartTimeKey) as? Date,
              let request = objc_getAssociatedObject(task, &taskRequestKey) as? URLRequest,
              let timestampWrapper = objc_getAssociatedObject(task, &taskResponseDataKey) as? TimestampWrapper
        else { return }

        let duration = Date().timeIntervalSince(startTime) * 1000
        let response = task.response as? HTTPURLResponse

        // Get accumulated response data if available
        let responseData = task.sr_accumulatedData

        // Clean up accumulated data
        task.sr_clearAccumulatedData()

        // Clean up observer
        objc_setAssociatedObject(task, &taskObserverKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        recordNetworkEntry(
            taskId: taskId,
            request: request,
            response: response,
            responseData: responseData,
            error: error,
            duration: duration,
            timestamp: timestampWrapper.timestamp
        )

        // Clean up associated objects
        objc_setAssociatedObject(task, &taskIdKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(task, &taskStartTimeKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(task, &taskRequestKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(task, &taskResponseDataKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    /// Called when data is received
    func taskDidReceiveData(_ task: URLSessionTask, data: Data) {
        guard isActive else { return }
        guard objc_getAssociatedObject(task, &taskIdKey) != nil else { return }

        // Accumulate data on the task using extension method
        task.sr_appendData(data)
    }

    // MARK: - Record Network Entry

    private func recordNetworkEntry(
        taskId: String,
        request: URLRequest,
        response: HTTPURLResponse?,
        responseData: Data?,
        error: Error?,
        duration: TimeInterval,
        timestamp: TimeInterval
    ) {
        guard let logger = logger else { return }

        let config = logger.currentConfig

        let requestHeaders = processHeaders(request.allHTTPHeaderFields, config: config)
        let responseHeaders = processHeaders(response?.allHeaderFields as? [String: String], config: config)

        let requestBody = processBody(request.httpBody, config: config)
        let responseBody = processBody(responseData, config: config)

        let entry = NetworkEntry(
            id: taskId,
            timestamp: timestamp,
            absoluteTime: Date(),
            method: request.httpMethod ?? "GET",
            url: request.url?.absoluteString ?? "",
            requestHeaders: requestHeaders,
            requestBody: requestBody?.content,
            requestBodySize: requestBody?.size,
            statusCode: response?.statusCode,
            responseHeaders: responseHeaders,
            responseBody: responseBody?.content,
            responseBodySize: responseBody?.size,
            duration: duration,
            error: error?.localizedDescription
        )

        logger.addNetworkEntry(entry)

        print("[SessionReplay] Network captured: \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "") -> \(response?.statusCode ?? 0) (\(Int(duration))ms)")
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

// MARK: - Timestamp Wrapper

private class TimestampWrapper {
    let timestamp: TimeInterval
    init(timestamp: TimeInterval) {
        self.timestamp = timestamp
    }
}

// MARK: - Task State Observer (KVO)

/// Observes URLSessionTask state changes using KVO to capture completion
/// for delegate-based tasks that don't use completion handlers.
private class TaskStateObserver: NSObject {
    private weak var task: URLSessionTask?
    private weak var interceptor: NetworkInterceptor?
    private var observation: NSKeyValueObservation?

    init(task: URLSessionTask, interceptor: NetworkInterceptor) {
        self.task = task
        self.interceptor = interceptor
        super.init()

        // Observe task state changes
        observation = task.observe(\.state, options: [.new]) { [weak self] task, change in
            guard let self = self else { return }

            if task.state == .completed {
                self.handleTaskCompletion(task)
            }
        }
    }

    private func handleTaskCompletion(_ task: URLSessionTask) {
        // Check if already handled (could be called from delegate too)
        let alreadyCompleted = objc_getAssociatedObject(task, &taskCompletedKey) as? Bool ?? false
        guard !alreadyCompleted else { return }
        objc_setAssociatedObject(task, &taskCompletedKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        // Notify interceptor of completion
        interceptor?.taskDidComplete(task, error: task.error)
    }

    deinit {
        observation?.invalidate()
    }
}

// MARK: - URLSessionTask Extension for Data Accumulation

private var accumulatedDataKey: UInt8 = 10

extension URLSessionTask {
    /// Get accumulated response data (works for any task type)
    var sr_accumulatedData: Data? {
        return objc_getAssociatedObject(self, &accumulatedDataKey) as? Data
    }

    /// Append data to accumulated response (works for any task type)
    func sr_appendData(_ data: Data) {
        // The completion-handler swizzles call this for every task once installed;
        // don't buffer response bodies when no session is recording.
        guard NetworkInterceptor.shared.isCapturing else { return }
        var accumulated = sr_accumulatedData ?? Data()
        accumulated.append(data)
        objc_setAssociatedObject(self, &accumulatedDataKey, accumulated, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    /// Clear accumulated data
    func sr_clearAccumulatedData() {
        objc_setAssociatedObject(self, &accumulatedDataKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

// MARK: - URLSession Method Swizzling

/// Comprehensive URLSession swizzling that captures ALL network requests.
final class URLSessionSwizzler {

    private static var hasSwizzled = false
    private static let swizzleLock = NSLock()

    // Store original implementations
    private static var originalResumeIMP: IMP?
    private static var originalDataTaskRequestCompletionIMP: IMP?
    private static var originalDataTaskURLCompletionIMP: IMP?
    private static var originalUploadTaskDataCompletionIMP: IMP?
    private static var originalUploadTaskFileCompletionIMP: IMP?
    private static var originalSessionInitIMP: IMP?

    /// Swizzle URLSession methods once. Safe to call multiple times.
    static func swizzleIfNeeded() {
        swizzleLock.lock()
        defer { swizzleLock.unlock() }

        guard !hasSwizzled else { return }
        hasSwizzled = true

        // CRITICAL: Swizzle URLSessionTask.resume - this catches ALL requests
        swizzleTaskResume()

        // Swizzle URLSession.init to inject proxy delegate
        swizzleSessionInit()

        // Swizzle completion handler methods
        swizzleDataTaskWithRequestAndCompletion()
        swizzleDataTaskWithURLAndCompletion()
        swizzleUploadTaskWithDataAndCompletion()
        swizzleUploadTaskWithFileAndCompletion()

        print("[SessionReplay] URLSession comprehensive swizzling complete")
    }

    // MARK: - URLSessionTask.resume Swizzling (CRITICAL)

    /// This is the most important swizzle - it catches ALL tasks when they start
    private static func swizzleTaskResume() {
        let selector = #selector(URLSessionTask.resume)

        guard let originalMethod = class_getInstanceMethod(URLSessionTask.self, selector) else {
            print("[SessionReplay] Failed to get URLSessionTask.resume method")
            return
        }

        let originalIMP = method_getImplementation(originalMethod)

        let block: @convention(block) (URLSessionTask) -> Void = { task in
            // Notify interceptor that task is about to resume
            NetworkInterceptor.shared.taskWillResume(task)

            // Call original implementation
            let original = unsafeBitCast(originalIMP, to: (@convention(c) (URLSessionTask, Selector) -> Void).self)
            original(task, selector)
        }

        let swizzledIMP = imp_implementationWithBlock(unsafeBitCast(block, to: AnyObject.self))
        method_setImplementation(originalMethod, swizzledIMP)

        print("[SessionReplay] Swizzled URLSessionTask.resume")
    }

    // MARK: - URLSession Delegate Injection

    /// Instead of swizzling URLSession.init (which is complex and error-prone),
    /// we use a combination of task.resume swizzling and completion handler wrapping.
    /// For delegate-based tasks, we capture what we can from the task properties.
    private static func swizzleSessionInit() {
        // Note: We're not swizzling URLSession.init because:
        // 1. It's a class cluster and the actual implementation varies
        // 2. Different networking libraries (Alamofire, FNetwork) may use different init patterns
        // 3. The task.resume swizzle + completion handler wrapping covers most cases
        //
        // For delegate-based tasks without completion handlers:
        // - We capture the request when resume is called
        // - We capture the response status/headers from task.response when available
        // - Response body capture requires the completion handler pattern
        print("[SessionReplay] Using task-level interception (no session init swizzle)")
    }

    // MARK: - Completion Handler Method Swizzling

    private static func swizzleDataTaskWithRequestAndCompletion() {
        let selector = #selector(URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URLRequest, @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask)

        guard let originalMethod = class_getInstanceMethod(URLSession.self, selector) else {
            print("[SessionReplay] Failed to get dataTask(with:completionHandler:) method")
            return
        }

        let originalIMP = method_getImplementation(originalMethod)

        let block: @convention(block) (URLSession, URLRequest, @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask = { session, request, completion in

            typealias DataTaskFunc = @convention(c) (URLSession, Selector, URLRequest, @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask

            // We need to capture task in a box since we create the wrapped completion before getting the task
            class TaskBox { weak var task: URLSessionDataTask? }
            let taskBox = TaskBox()

            // Wrap completion to capture response data
            let wrappedCompletion: (Data?, URLResponse?, Error?) -> Void = { data, response, error in
                // Store response data on the task for the interceptor to pick up
                if let task = taskBox.task, let data = data {
                    task.sr_appendData(data)
                }
                completion(data, response, error)
            }

            let original = unsafeBitCast(originalIMP, to: DataTaskFunc.self)
            let task = original(session, selector, request, wrappedCompletion)
            taskBox.task = task
            return task
        }

        let swizzledIMP = imp_implementationWithBlock(unsafeBitCast(block, to: AnyObject.self))
        method_setImplementation(originalMethod, swizzledIMP)
    }

    private static func swizzleDataTaskWithURLAndCompletion() {
        let selector = #selector(URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URL, @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask)

        guard let originalMethod = class_getInstanceMethod(URLSession.self, selector) else {
            return
        }

        let originalIMP = method_getImplementation(originalMethod)

        let block: @convention(block) (URLSession, URL, @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask = { session, url, completion in
            typealias DataTaskFunc = @convention(c) (URLSession, Selector, URL, @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask

            class TaskBox { weak var task: URLSessionDataTask? }
            let taskBox = TaskBox()

            let wrappedCompletion: (Data?, URLResponse?, Error?) -> Void = { data, response, error in
                if let task = taskBox.task, let data = data {
                    task.sr_appendData(data)
                }
                completion(data, response, error)
            }

            let original = unsafeBitCast(originalIMP, to: DataTaskFunc.self)
            let task = original(session, selector, url, wrappedCompletion)
            taskBox.task = task
            return task
        }

        let swizzledIMP = imp_implementationWithBlock(unsafeBitCast(block, to: AnyObject.self))
        method_setImplementation(originalMethod, swizzledIMP)
    }

    private static func swizzleUploadTaskWithDataAndCompletion() {
        let selector = #selector(URLSession.uploadTask(with:from:completionHandler:) as (URLSession) -> (URLRequest, Data?, @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionUploadTask)

        guard let originalMethod = class_getInstanceMethod(URLSession.self, selector) else {
            return
        }

        let originalIMP = method_getImplementation(originalMethod)

        let block: @convention(block) (URLSession, URLRequest, Data?, @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionUploadTask = { session, request, bodyData, completion in
            typealias UploadTaskFunc = @convention(c) (URLSession, Selector, URLRequest, Data?, @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionUploadTask

            class TaskBox { weak var task: URLSessionUploadTask? }
            let taskBox = TaskBox()

            let wrappedCompletion: (Data?, URLResponse?, Error?) -> Void = { data, response, error in
                if let task = taskBox.task, let data = data {
                    task.sr_appendData(data)
                }
                completion(data, response, error)
            }

            let original = unsafeBitCast(originalIMP, to: UploadTaskFunc.self)
            let task = original(session, selector, request, bodyData, wrappedCompletion)
            taskBox.task = task
            return task
        }

        let swizzledIMP = imp_implementationWithBlock(unsafeBitCast(block, to: AnyObject.self))
        method_setImplementation(originalMethod, swizzledIMP)
    }

    private static func swizzleUploadTaskWithFileAndCompletion() {
        let selector = #selector(URLSession.uploadTask(with:fromFile:completionHandler:) as (URLSession) -> (URLRequest, URL, @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionUploadTask)

        guard let originalMethod = class_getInstanceMethod(URLSession.self, selector) else {
            return
        }

        let originalIMP = method_getImplementation(originalMethod)

        let block: @convention(block) (URLSession, URLRequest, URL, @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionUploadTask = { session, request, fileURL, completion in
            typealias UploadTaskFunc = @convention(c) (URLSession, Selector, URLRequest, URL, @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionUploadTask

            class TaskBox { weak var task: URLSessionUploadTask? }
            let taskBox = TaskBox()

            let wrappedCompletion: (Data?, URLResponse?, Error?) -> Void = { data, response, error in
                if let task = taskBox.task, let data = data {
                    task.sr_appendData(data)
                }
                completion(data, response, error)
            }

            let original = unsafeBitCast(originalIMP, to: UploadTaskFunc.self)
            let task = original(session, selector, request, fileURL, wrappedCompletion)
            taskBox.task = task
            return task
        }

        let swizzledIMP = imp_implementationWithBlock(unsafeBitCast(block, to: AnyObject.self))
        method_setImplementation(originalMethod, swizzledIMP)
    }
}
