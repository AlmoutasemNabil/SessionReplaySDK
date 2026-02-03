//
//  SwiftUIIntegration.swift
//  SessionReplaySDK
//
//  SwiftUI-specific integration for session replay.
//  Provides view modifiers, replay viewer, and session list components.
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

#endif
