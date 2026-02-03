//
//  UIKitIntegration.swift
//  SessionReplaySDK
//
//  UIKit-specific integration for session replay.
//  Provides base classes, extensions, and debug view controller.
//
//  Created by AlmoutasemNabil on 2026.
//  Copyright © 2026 AlmoutasemNabil. All rights reserved.
//
//  This source code is licensed under the MIT license found in the
//  LICENSE file in the root directory of this source tree.
//

#if canImport(UIKit)
import UIKit
import AVKit

// MARK: - Session Replay View Controller

/// Base view controller that automatically tracks screen views
open class SessionReplayViewController: UIViewController {

    /// Override to provide a custom screen name (defaults to class name)
    open var screenName: String {
        return String(describing: type(of: self))
    }

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        SessionReplayManager.shared.trackScreen(screenName)
    }
}

// MARK: - Maskable Protocol

/// Protocol for views that should be masked in replay
public protocol SessionReplayMaskable {
    var shouldMaskInReplay: Bool { get }
}

/// A view that is automatically masked in session replays
public class MaskedView: UIView, SessionReplayMaskable {
    public var shouldMaskInReplay: Bool = true
    public var maskColor: UIColor = .gray

    public override func draw(_ rect: CGRect) {
        super.draw(rect)
    }
}

// MARK: - UIView Extensions

public extension UIView {

    /// Mark this view as containing sensitive data
    func markAsSensitive() {
        if accessibilityIdentifier == nil {
            accessibilityIdentifier = "sr-no-capture"
        } else if !accessibilityIdentifier!.contains("sr-no-capture") {
            accessibilityIdentifier = accessibilityIdentifier! + " sr-no-capture"
        }
    }

    /// Check if this view is marked as sensitive
    var isSensitive: Bool {
        return accessibilityIdentifier?.contains("sr-no-capture") ?? false
    }

    /// Capture a snapshot of this view
    func captureSnapshot(afterScreenUpdates: Bool = false) -> UIImage {
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { _ in
            drawHierarchy(in: bounds, afterScreenUpdates: afterScreenUpdates)
        }
    }
}

// MARK: - UIWindow Extensions

public extension UIWindow {

    /// Get the currently visible view controller
    var visibleViewController: UIViewController? {
        return getVisibleViewController(from: rootViewController)
    }

    private func getVisibleViewController(from vc: UIViewController?) -> UIViewController? {
        if let nav = vc as? UINavigationController {
            return getVisibleViewController(from: nav.visibleViewController)
        }
        if let tab = vc as? UITabBarController {
            return getVisibleViewController(from: tab.selectedViewController)
        }
        if let presented = vc?.presentedViewController {
            return getVisibleViewController(from: presented)
        }
        return vc
    }
}

// MARK: - Touch Visualization View

/// View that displays touch indicators
public class TouchVisualizationView: UIView {

    private var touchIndicators: [UITouch: UIView] = [:]

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    public func updateTouches(_ touches: Set<UITouch>) {
        for touch in touches {
            switch touch.phase {
            case .began:
                addIndicator(for: touch)
            case .moved:
                moveIndicator(for: touch)
            case .ended, .cancelled:
                removeIndicator(for: touch)
            default:
                break
            }
        }
    }

    private func addIndicator(for touch: UITouch) {
        let indicator = createIndicatorView()
        indicator.center = touch.location(in: self)
        addSubview(indicator)
        touchIndicators[touch] = indicator

        indicator.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        UIView.animate(withDuration: 0.15) {
            indicator.transform = .identity
        }
    }

    private func moveIndicator(for touch: UITouch) {
        guard let indicator = touchIndicators[touch] else { return }
        indicator.center = touch.location(in: self)
    }

    private func removeIndicator(for touch: UITouch) {
        guard let indicator = touchIndicators[touch] else { return }

        UIView.animate(withDuration: 0.2, animations: {
            indicator.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
            indicator.alpha = 0
        }) { _ in
            indicator.removeFromSuperview()
        }

        touchIndicators.removeValue(forKey: touch)
    }

    private func createIndicatorView() -> UIView {
        let size: CGFloat = 44
        let view = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        view.backgroundColor = UIColor.red.withAlphaComponent(0.3)
        view.layer.cornerRadius = size / 2
        view.layer.borderWidth = 2
        view.layer.borderColor = UIColor.red.cgColor
        return view
    }
}

// MARK: - Debug View Controller

/// Debug view controller for testing session replay
public class SessionReplayDebugViewController: UIViewController {

    private let statusLabel = UILabel()
    private let frameCountLabel = UILabel()
    private let touchCountLabel = UILabel()
    private let startStopButton = UIButton(type: .system)
    private let viewSessionsButton = UIButton(type: .system)
    private let uploadButton = UIButton(type: .system)

    private var updateTimer: Timer?

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        startUpdateTimer()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        updateTimer?.invalidate()
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground
        title = "Session Replay Debug"

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20)
        ])

        // Status
        statusLabel.font = .systemFont(ofSize: 24, weight: .bold)
        statusLabel.textAlignment = .center
        stack.addArrangedSubview(statusLabel)

        // Frame count
        frameCountLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .regular)
        frameCountLabel.textColor = .secondaryLabel
        stack.addArrangedSubview(frameCountLabel)

        // Touch count
        touchCountLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .regular)
        touchCountLabel.textColor = .secondaryLabel
        stack.addArrangedSubview(touchCountLabel)

        // Spacer
        let spacer = UIView()
        spacer.heightAnchor.constraint(equalToConstant: 20).isActive = true
        stack.addArrangedSubview(spacer)

        // Start/Stop button
        startStopButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        startStopButton.addTarget(self, action: #selector(toggleRecording), for: .touchUpInside)
        stack.addArrangedSubview(startStopButton)

        // View sessions button
        viewSessionsButton.setTitle("View Recorded Sessions", for: .normal)
        viewSessionsButton.titleLabel?.font = .systemFont(ofSize: 16)
        viewSessionsButton.addTarget(self, action: #selector(viewSessions), for: .touchUpInside)
        stack.addArrangedSubview(viewSessionsButton)

        // Upload button
        uploadButton.setTitle("Upload All Sessions", for: .normal)
        uploadButton.titleLabel?.font = .systemFont(ofSize: 16)
        uploadButton.addTarget(self, action: #selector(uploadAllSessions), for: .touchUpInside)
        stack.addArrangedSubview(uploadButton)

        updateUI()
    }

    private func startUpdateTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateUI()
        }
    }

    private func updateUI() {
        let manager = SessionReplayManager.shared
        let isRecording = manager.isRecording

        statusLabel.text = isRecording ? "🔴 Recording" : "⚪ Stopped"
        statusLabel.textColor = isRecording ? .systemRed : .label

        let frameCount = manager.currentSession?.frameCount ?? 0
        let touchCount = manager.currentSession?.touchEvents?.count ?? 0

        frameCountLabel.text = "Frames: \(frameCount)"
        touchCountLabel.text = "Touch Events: \(touchCount)"

        startStopButton.setTitle(isRecording ? "Stop Recording" : "Start Recording", for: .normal)
        startStopButton.tintColor = isRecording ? .systemRed : .systemGreen

        uploadButton.isEnabled = SessionUploader.shared.isConfigured
        uploadButton.alpha = SessionUploader.shared.isConfigured ? 1.0 : 0.5
    }

    @objc private func toggleRecording() {
        let manager = SessionReplayManager.shared
        if manager.isRecording {
            manager.stopSession()
        } else {
            manager.startSession()
        }
        updateUI()
    }

    @objc private func viewSessions() {
        let sessions = SessionReplayManager.shared.getSavedSessions()

        let alert = UIAlertController(
            title: "Recorded Sessions",
            message: "Found \(sessions.count) session(s)",
            preferredStyle: .actionSheet
        )

        for session in sessions.prefix(5) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            dateFormatter.timeStyle = .short

            let title = "\(dateFormatter.string(from: session.startTime)) (\(session.frameCount) frames)"
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.playSession(session)
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = viewSessionsButton
            popover.sourceRect = viewSessionsButton.bounds
        }

        present(alert, animated: true)
    }

    @objc private func uploadAllSessions() {
        guard SessionUploader.shared.isConfigured else {
            showAlert(title: "Not Configured", message: "Upload service is not configured")
            return
        }

        SessionUploader.shared.uploadAllPendingSessions { [weak self] results in
            let successCount = results.filter { _, result in
                if case .success = result { return true }
                return false
            }.count

            self?.showAlert(
                title: "Upload Complete",
                message: "\(successCount) of \(results.count) sessions uploaded successfully"
            )
        }
    }

    private func playSession(_ session: SessionReplayData) {
        guard let videoURL = SessionReplayManager.shared.getVideoURL(for: session) else {
            showAlert(title: "Error", message: "Video file not found")
            return
        }

        let playerVC = AVPlayerViewController()
        playerVC.player = AVPlayer(url: videoURL)
        present(playerVC, animated: true) {
            playerVC.player?.play()
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

#endif
