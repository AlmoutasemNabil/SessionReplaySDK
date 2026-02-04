//
//  SwiftUIIntegration.swift
//  SessionReplaySDK
//
//  SwiftUI-specific integration for session replay.
//  Provides view modifiers, replay viewer, and session list components.
//
//  Created by AlmoutasemNabil on 2026.
//  Copyright © 2026 AlmoutasemNabil. All rights reserved.
//
//  This source code is licensed under the MIT license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
import AVKit

// MARK: - View Modifiers

/// View modifier for tracking screen views
public struct ScreenTrackingModifier: ViewModifier {
    let screenName: String

    public func body(content: Content) -> some View {
        content
            .onAppear {
                SessionReplayManager.shared.trackScreen(screenName)
            }
    }
}

/// Touch indicator overlay for visual feedback
public struct TouchIndicatorOverlay: View {
    @State private var touches: [CapturedTouchEvent] = []
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    public init() {}

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(touches.indices, id: \.self) { index in
                    let touch = touches[index]
                    Circle()
                        .fill(Color.red.opacity(0.5))
                        .frame(width: 40, height: 40)
                        .position(touch.location)
                        .animation(.easeOut(duration: 0.3), value: touch.location)
                }
            }
        }
        .allowsHitTesting(false)
        .onReceive(timer) { _ in
            updateTouches()
        }
    }

    private func updateTouches() {
        guard let session = SessionReplayManager.shared.currentSession else {
            touches = []
            return
        }

        let recentTouches = session.touchEvents?.suffix(20).filter { touch in
            touch.phase == UITouch.Phase.began.rawValue || touch.phase == UITouch.Phase.moved.rawValue
        }
        touches = Array(recentTouches?.suffix(5) ?? [])
    }
}

// MARK: - Session Replay Viewer

/// View for playing back a recorded session
public struct SessionReplayViewer: View {
    let session: SessionReplayData
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var currentSegmentIndex = 0
    @State private var videoFileSize: String = "Unknown"

    public init(session: SessionReplayData) {
        self.session = session
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Video Player
                if let player = player {
                    VideoPlayer(player: player)
                        .frame(maxWidth: .infinity)
                        .frame(height: UIScreen.main.bounds.height * 0.5)
                        .cornerRadius(12)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .aspectRatio(9/16, contentMode: .fit)
                        .cornerRadius(12)
                        .overlay(
                            Text("No video available")
                                .foregroundColor(.secondary)
                        )
                }

                // Playback Controls
                HStack(spacing: 20) {
                    Button(action: seekBackward) {
                        Image(systemName: "gobackward.10")
                            .font(.title2)
                    }

                    Button(action: togglePlayback) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.title)
                    }

                    Button(action: seekForward) {
                        Image(systemName: "goforward.10")
                            .font(.title2)
                    }
                }
                .padding()

                // Session Info
                VStack(alignment: .leading, spacing: 8) {
                    Text("Session Info")
                        .font(.headline)

                    Group {
                        InfoRow(label: "Session ID", value: String(session.sessionId.prefix(8)))
                        InfoRow(label: "Started", value: formatDate(session.startTime))
                        InfoRow(label: "Frames", value: "\(session.frameCount)")
                        InfoRow(label: "Touch Events", value: "\(session.touches.count)")
                        InfoRow(label: "Logs", value: "\(session.logs.count)")
                        InfoRow(label: "Segments", value: "\(session.videoSegments.count)")
                        InfoRow(label: "Video Size", value: videoFileSize)
                    }
                    .font(.caption)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .onAppear(perform: setupPlayer)
        .onDisappear {
            player?.pause()
        }
    }

    private func setupPlayer() {
        guard let url = SessionReplayManager.shared.getVideoURL(for: session) else {
            return
        }

        player = AVPlayer(url: url)

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { _ in
            player?.seek(to: .zero)
            isPlaying = false
        }

        getVideoFileSize()
    }

    private func togglePlayback() {
        if isPlaying {
            player?.pause()
        } else {
            player?.play()
        }
        isPlaying.toggle()
    }

    private func seekBackward() {
        guard let player = player,
              let currentTime = player.currentItem?.currentTime() else { return }
        let newTime = CMTimeSubtract(currentTime, CMTime(seconds: 10, preferredTimescale: 1))
        player.seek(to: newTime)
    }

    private func seekForward() {
        guard let player = player,
              let currentTime = player.currentItem?.currentTime() else { return }
        let newTime = CMTimeAdd(currentTime, CMTime(seconds: 10, preferredTimescale: 1))
        player.seek(to: newTime)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func getVideoFileSize() {
        guard let url = SessionReplayManager.shared.getVideoURL(for: session) else {
            videoFileSize = "Not found"
            return
        }

        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? Int64 {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB]
            formatter.countStyle = .file
            videoFileSize = formatter.string(fromByteCount: size)
        }
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Sessions List View

/// View for listing and managing recorded sessions
public struct SessionsListView: View {
    @State private var sessions: [SessionReplayData] = []
    @State private var selectedSession: SessionReplayData?
    @State private var isUploading: [String: Bool] = [:]
    @State private var uploadError: String?
    @State private var showingUploadError = false

    public init() {}

    public var body: some View {
        NavigationView {
            List {
                if sessions.isEmpty {
                    Text("No recorded sessions")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(sessions) { session in
                        SessionRow(
                            session: session,
                            isUploading: isUploading[session.sessionId] ?? false,
                            onUpload: { uploadSession(session) }
                        )
                        .onTapGesture {
                            selectedSession = session
                        }
                    }
                    .onDelete(perform: deleteSessions)
                }
            }
            .navigationTitle("Session Replays")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh") {
                        loadSessions()
                    }
                }
            }
            .onAppear(perform: loadSessions)
            .alert("Upload Error", isPresented: $showingUploadError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(uploadError ?? "Unknown error")
            }

            if let session = selectedSession {
                SessionReplayViewer(session: session)
            } else {
                Text("Select a session")
                    .foregroundColor(.secondary)
            }
        }
    }

    private func loadSessions() {
        sessions = SessionReplayManager.shared.getSavedSessions()
    }

    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            SessionReplayManager.shared.deleteSession(sessions[index])
        }
        sessions.remove(atOffsets: offsets)
    }

    private func uploadSession(_ session: SessionReplayData) {
        guard SessionUploader.shared.isConfigured else {
            uploadError = "Upload service not configured. Call SessionUploader.shared.configure() first."
            showingUploadError = true
            return
        }

        isUploading[session.sessionId] = true

        SessionUploader.shared.uploadSession(session) { result in
            DispatchQueue.main.async {
                isUploading[session.sessionId] = false

                switch result {
                case .success:
                    // Optionally refresh or show success message
                    break
                case .failure(let error):
                    uploadError = error.localizedDescription
                    showingUploadError = true
                }
            }
        }
    }
}

// MARK: - Session Row

struct SessionRow: View {
    let session: SessionReplayData
    let isUploading: Bool
    let onUpload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(formatDate(session.startTime))
                    .font(.headline)

                Spacer()

                if isUploading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button(action: onUpload) {
                        Image(systemName: "icloud.and.arrow.up")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
            }

            HStack(spacing: 12) {
                Label("\(session.frameCount) frames", systemImage: "photo.stack")
                Label("\(session.touches.count) touches", systemImage: "hand.tap")
                Label("\(session.logs.count) logs", systemImage: "doc.text")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - View Extensions

public extension View {
    /// Track this view as a screen in session replay
    func trackScreen(_ name: String) -> some View {
        modifier(ScreenTrackingModifier(screenName: name))
    }

    /// Add touch indicators overlay
    func withTouchIndicators() -> some View {
        ZStack {
            self
            TouchIndicatorOverlay()
        }
    }

    /// Mark this view as containing sensitive data that should be masked in replay
    /// The view will be replaced with a gray box in the recorded video
    func sensitiveContent() -> some View {
        modifier(SensitiveContentModifier())
    }

    /// Mark this view as containing sensitive data with custom mask color
    func sensitiveContent(maskColor: Color) -> some View {
        modifier(SensitiveContentModifier(maskColor: maskColor))
    }
}

// MARK: - Sensitive Content Modifier

/// View modifier that marks a view as containing sensitive data
public struct SensitiveContentModifier: ViewModifier {
    var maskColor: Color = Color.gray

    public init(maskColor: Color = .gray) {
        self.maskColor = maskColor
    }

    public func body(content: Content) -> some View {
        content
            .background(
                SensitiveMarkerView()
            )
    }
}

/// UIViewRepresentable that marks the hosting view as sensitive
struct SensitiveMarkerView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        // Mark as sensitive using the accessibility identifier approach
        view.accessibilityIdentifier = "sr-no-capture"
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Ensure the parent view hierarchy is also marked
        DispatchQueue.main.async {
            // Walk up the view hierarchy and mark the first significant view
            var current: UIView? = uiView.superview
            while let view = current {
                if view.bounds.size != .zero {
                    view.markAsSensitive()
                    break
                }
                current = view.superview
            }
        }
    }
}

// MARK: - Recording Control View

/// A simple view for controlling recording state
public struct RecordingControlView: View {
    @State private var isRecording = false
    @State private var frameCount = 0
    @State private var touchCount = 0

    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            // Status
            HStack {
                Circle()
                    .fill(isRecording ? Color.red : Color.gray)
                    .frame(width: 12, height: 12)

                Text(isRecording ? "Recording" : "Stopped")
                    .font(.headline)
            }

            // Stats
            if isRecording {
                HStack(spacing: 20) {
                    Label("\(frameCount)", systemImage: "photo")
                    Label("\(touchCount)", systemImage: "hand.tap")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            // Control Button
            Button(action: toggleRecording) {
                Text(isRecording ? "Stop Recording" : "Start Recording")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(isRecording ? Color.red : Color.green)
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 4)
        .onReceive(timer) { _ in
            updateStats()
        }
    }

    private func toggleRecording() {
        if isRecording {
            SessionReplayManager.shared.stopSession()
        } else {
            SessionReplayManager.shared.startSession()
        }
        isRecording.toggle()
    }

    private func updateStats() {
        isRecording = SessionReplayManager.shared.isRecording
        frameCount = SessionReplayManager.shared.currentSession?.frameCount ?? 0
        touchCount = SessionReplayManager.shared.currentSession?.touchEvents?.count ?? 0
    }
}

// MARK: - Activity Timeline View

/// Unified activity entry type for timeline display
public enum SDKActivityEntry: Identifiable {
    case log(LogEntry)
    case network(NetworkEntry)

    public var id: String {
        switch self {
        case .log(let entry): return "log-\(entry.timestamp)-\(entry.message.hashValue)"
        case .network(let entry): return "net-\(entry.id)"
        }
    }

    public var timestamp: TimeInterval {
        switch self {
        case .log(let entry): return entry.timestamp
        case .network(let entry): return entry.timestamp
        }
    }
}

/// A beautiful activity timeline view showing logs and network requests
public struct ActivityTimelineView: View {
    let session: SessionReplayData
    @State private var filterType: ActivityFilterType = .all
    @State private var searchText: String = ""
    @State private var expandedEntryId: String? = nil

    public enum ActivityFilterType: String, CaseIterable {
        case all = "All"
        case logs = "Logs"
        case network = "Network"
        case errors = "Errors"

        var icon: String {
            switch self {
            case .all: return "list.bullet"
            case .logs: return "doc.text"
            case .network: return "network"
            case .errors: return "exclamationmark.triangle"
            }
        }
    }

    public init(session: SessionReplayData) {
        self.session = session
    }

    // Build activity list, filtering out SDK touch logs
    var allActivity: [SDKActivityEntry] {
        var entries: [SDKActivityEntry] = []
        let filteredLogs = session.logs.filter { log in
            !log.message.contains("[SessionReplay] Touch")
        }
        entries.append(contentsOf: filteredLogs.map { .log($0) })
        entries.append(contentsOf: session.networkRequests.map { .network($0) })
        return entries.sorted { $0.timestamp < $1.timestamp }
    }

    var filteredActivity: [SDKActivityEntry] {
        var result = allActivity

        // Apply type filter
        switch filterType {
        case .all:
            break
        case .logs:
            result = result.filter { if case .log = $0 { return true } else { return false } }
        case .network:
            result = result.filter { if case .network = $0 { return true } else { return false } }
        case .errors:
            result = result.filter { entry in
                switch entry {
                case .log(let log): return log.level == .error || log.level == .warning
                case .network(let req): return (req.statusCode ?? 0) >= 400
                }
            }
        }

        // Apply search filter
        if !searchText.isEmpty {
            result = result.filter { entry in
                switch entry {
                case .log(let log):
                    return log.message.localizedCaseInsensitiveContains(searchText)
                case .network(let req):
                    return req.url.localizedCaseInsensitiveContains(searchText) ||
                           req.method.localizedCaseInsensitiveContains(searchText)
                }
            }
        }

        return result
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header with stats
            headerSection

            // Filter chips
            filterSection

            // Search bar
            searchSection

            // Timeline
            timelineSection
        }
        .background(Color(.systemGroupedBackground))
    }

    private var headerSection: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Activity Timeline")
                    .font(.headline)
                Text(session.sessionId.prefix(8) + "...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                StatBadge(value: session.logs.count, label: "Logs", color: .blue)
                StatBadge(value: session.networkRequests.count, label: "Network", color: .green)
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }

    private var filterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ActivityFilterType.allCases, id: \.self) { type in
                    FilterChip(
                        title: type.rawValue,
                        icon: type.icon,
                        isSelected: filterType == type,
                        count: countForFilter(type)
                    )
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            filterType = type
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
    }

    private var searchSection: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search logs and requests...", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var timelineSection: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if filteredActivity.isEmpty {
                    emptyStateView
                } else {
                    ForEach(Array(filteredActivity.enumerated()), id: \.element.id) { index, entry in
                        ActivityTimelineRow(
                            entry: entry,
                            isExpanded: expandedEntryId == entry.id,
                            isFirst: index == 0,
                            isLast: index == filteredActivity.count - 1
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if expandedEntryId == entry.id {
                                    expandedEntryId = nil
                                } else {
                                    expandedEntryId = entry.id
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No activity found")
                .font(.headline)
                .foregroundColor(.secondary)
            if !searchText.isEmpty {
                Text("Try a different search term")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func countForFilter(_ type: ActivityFilterType) -> Int {
        switch type {
        case .all: return allActivity.count
        case .logs: return session.logs.filter { !$0.message.contains("[SessionReplay] Touch") }.count
        case .network: return session.networkRequests.count
        case .errors:
            let errorLogs = session.logs.filter { $0.level == .error || $0.level == .warning }.count
            let errorRequests = session.networkRequests.filter { ($0.statusCode ?? 0) >= 400 }.count
            return errorLogs + errorRequests
        }
    }
}

// MARK: - Activity Timeline Row

struct ActivityTimelineRow: View {
    let entry: SDKActivityEntry
    let isExpanded: Bool
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Timeline indicator
            VStack(spacing: 0) {
                if !isFirst {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 2, height: 12)
                }

                Circle()
                    .fill(dotColor)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(dotColor.opacity(0.3), lineWidth: 3)
                    )

                if !isLast {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 20)

            // Content
            VStack(alignment: .leading, spacing: 6) {
                // Timestamp
                Text(formatTimestamp(entry.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fontWeight(.medium)

                // Entry content
                switch entry {
                case .log(let log):
                    logContent(log)
                case .network(let req):
                    networkContent(req)
                }
            }
            .padding(.vertical, 8)
            .padding(.trailing, 12)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .background(isExpanded ? Color.blue.opacity(0.05) : Color.clear)
    }

    private var dotColor: Color {
        switch entry {
        case .log(let log):
            switch log.level {
            case .debug: return .gray
            case .info: return .blue
            case .warning: return .orange
            case .error: return .red
            }
        case .network(let req):
            if let status = req.statusCode {
                return status >= 400 ? .red : .green
            }
            return .blue
        }
    }

    @ViewBuilder
    private func logContent(_ log: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(logLevelIcon(log.level))
                .font(.caption)

            VStack(alignment: .leading, spacing: 4) {
                Text(log.message)
                    .font(.callout)
                    .foregroundColor(logLevelColor(log.level))
                    .lineLimit(isExpanded ? nil : 2)

                if isExpanded {
                    HStack(spacing: 8) {
                        Label(log.level.rawValue.capitalized, systemImage: "flag")
                        Label(log.source, systemImage: "terminal")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func networkContent(_ req: NetworkEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Method + Status + Duration
            HStack(spacing: 8) {
                Text("🌐")
                    .font(.caption)

                Text(req.method)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)

                if let status = req.statusCode {
                    Text("\(status)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(status < 400 ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                        .foregroundColor(status < 400 ? .green : .red)
                        .cornerRadius(4)
                }

                if let duration = req.duration {
                    Text(String(format: "%.0fms", duration))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // URL
            Text(req.url)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(isExpanded ? nil : 1)

            // Expanded details
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if let headers = req.requestHeaders, !headers.isEmpty {
                        ExpandableSection(title: "Request Headers") {
                            ForEach(Array(headers.keys.sorted()), id: \.self) { key in
                                HStack {
                                    Text(key)
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text(headers[key] ?? "")
                                        .foregroundColor(.secondary)
                                }
                                .font(.caption2)
                            }
                        }
                    }

                    if let body = req.requestBody, !body.isEmpty {
                        ExpandableSection(title: "Request Body") {
                            Text(body)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let body = req.responseBody, !body.isEmpty {
                        ExpandableSection(title: "Response Body") {
                            Text(body.prefix(500) + (body.count > 500 ? "..." : ""))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let error = req.error {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func formatTimestamp(_ ms: TimeInterval) -> String {
        let totalSeconds = Int(ms / 1000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let millis = Int(ms) % 1000
        return String(format: "+%d:%02d.%03d", minutes, seconds, millis)
    }

    private func logLevelIcon(_ level: LogLevel) -> String {
        switch level {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        }
    }

    private func logLevelColor(_ level: LogLevel) -> Color {
        switch level {
        case .debug: return .gray
        case .info: return .primary
        case .warning: return .orange
        case .error: return .red
        }
    }
}

// MARK: - Supporting Views

struct StatBadge: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.headline)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

struct FilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(title)
                .font(.subheadline)
            Text("\(count)")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(isSelected ? Color.white.opacity(0.3) : Color.gray.opacity(0.2))
                .cornerRadius(8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.blue : Color(.secondarySystemBackground))
        .foregroundColor(isSelected ? .white : .primary)
        .cornerRadius(20)
    }
}

struct ExpandableSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            content()
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(6)
        }
    }
}

// MARK: - Live Activity View (Real-time during recording)

/// A live activity view that updates in real-time during recording
public struct LiveActivityView: View {
    @State private var logs: [LogEntry] = []
    @State private var networkRequests: [NetworkEntry] = []
    @State private var isRecording = false

    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    public init() {}

    var allActivity: [SDKActivityEntry] {
        var entries: [SDKActivityEntry] = []
        let filteredLogs = logs.filter { !$0.message.contains("[SessionReplay] Touch") }
        entries.append(contentsOf: filteredLogs.map { .log($0) })
        entries.append(contentsOf: networkRequests.map { .network($0) })
        return entries.sorted { $0.timestamp < $1.timestamp }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Circle()
                    .fill(isRecording ? Color.red : Color.gray)
                    .frame(width: 10, height: 10)
                Text(isRecording ? "Recording..." : "Not Recording")
                    .font(.headline)
                Spacer()
                Text("\(allActivity.count) events")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemBackground))

            Divider()

            // Activity list
            if allActivity.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: isRecording ? "waveform" : "pause.circle")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text(isRecording ? "Waiting for activity..." : "Start recording to see activity")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(allActivity.enumerated()), id: \.element.id) { index, entry in
                                ActivityTimelineRow(
                                    entry: entry,
                                    isExpanded: false,
                                    isFirst: index == 0,
                                    isLast: index == allActivity.count - 1
                                )
                                .id(entry.id)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .onChange(of: allActivity.count) { _ in
                        if let lastId = allActivity.last?.id {
                            withAnimation {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .onReceive(timer) { _ in
            updateActivity()
        }
    }

    private func updateActivity() {
        isRecording = SessionReplayManager.shared.isRecording
        logs = SessionLogger.shared.getLogs()
        networkRequests = SessionLogger.shared.getNetworkRequests()
    }
}

#endif
