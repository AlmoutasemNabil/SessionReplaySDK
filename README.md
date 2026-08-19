# SessionReplaySDK

<p align="center">
  <img src="https://img.shields.io/badge/Version-0.2.2-blue.svg" alt="Version 0.2.2"/>
  <img src="https://img.shields.io/badge/Platform-iOS%2015%2B-blue.svg" alt="Platform iOS 15+"/>
  <img src="https://img.shields.io/badge/Swift-5.9%2B-orange.svg" alt="Swift 5.9+"/>
  <img src="https://img.shields.io/badge/License-MIT-green.svg" alt="MIT License"/>
  <img src="https://img.shields.io/badge/SPM-Compatible-brightgreen.svg" alt="SPM Compatible"/>
</p>

<p align="center">
  <strong>A powerful, privacy-focused session replay SDK for iOS applications.</strong>
</p>



<p align="center">
  Capture user sessions with video recording, touch visualization, console logs, and network requests—all synchronized for powerful debugging and UX analysis.
</p>

<p align="center">
  <strong>A complete demo application <a href="https://github.com/AlmoutasemNabil/SessionReplayDemo">SessionReplayDemo</a> </strong>
</p>

---

## Features

| Feature | Description |
|---------|-------------|
| **Video Recording** | H.264 encoded screen capture with configurable quality and frame rate |
| **Touch Visualization** | Record and overlay touch events with visual indicators |
| **Console Log Capture** | Automatically intercept `print()`, `NSLog()`, and stderr |
| **Network Tracking** | Monitor all HTTP/HTTPS requests (works with Alamofire SSL pinning) |
| **User Identification** | Attach user info (userId, email, custom data) to sessions |
| **Auto Start/Stop** | Configurable automatic session lifecycle management |
| **Crash Recovery** | Periodic checkpoints to recover sessions after crashes |
| **App Groups** | Share session data between app and extensions |
| **Screen Transitions** | Track navigation flow between screens |
| **Synchronized Timeline** | All events timestamped for video sync playback |
| **Local Storage** | Save sessions locally with JSON metadata |
| **Cloud Upload** | Multipart form data upload to your backend |
| **Privacy Controls** | Redact headers, exclude URLs, sanitize logs |
| **SwiftUI & UIKit** | Full support with view modifiers and components |

## Installation

### Swift Package Manager

**Xcode:**
1. Go to **File > Add Package Dependencies**
2. Enter: `https://github.com/AlmoutasemNabil/SessionReplaySDK`
3. Select version and add to your target

**Package.swift:**
```swift
dependencies: [
    .package(url: "https://github.com/AlmoutasemNabil/SessionReplaySDK", from: "0.2.0")
]
```

## Quick Start

### 1. Configure on App Launch

```swift
import SessionReplaySDK

@main
struct MyApp: App {
    init() {
        var config = SessionReplayConfig()
        config.captureFrameRate = 10
        config.jpegCompressionQuality = 0.7
        config.autoStartOnLaunch = false    // Manual control
        config.enableCrashRecovery = true   // Save on crash
        config.debugLogging = false         // Disable in production

        SessionReplaySDK.configure(
            videoConfig: config,
            logConfig: SessionLoggerConfig()
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### 2. Logs-Only Mode (No Video)

For lightweight logging without video recording:

```swift
var config = SessionReplayConfig()
config.enableVideoRecording = false  // Disable video, capture logs only

SessionReplaySDK.configure(
    videoConfig: config,
    logConfig: SessionLoggerConfig()
)

// Start/stop works the same way
SessionReplaySDK.start()
// ... session captures console logs and network requests only
SessionReplaySDK.stop()
```

### 3. Identify Users

```swift
// After user logs in
SessionReplaySDK.identifyUser(
    userId: "user_123",
    email: "user@example.com",
    name: "John Doe",
    additionalInfo: ["plan": "premium", "branchId": "branch_456"]
)

// Or set custom info directly
SessionReplaySDK.setUserInfo([
    "userId": "123",
    "email": "user@example.com",
    "customField": "value"
])
```

### 3. Start/Stop Recording

```swift
// Start recording
SessionReplaySDK.startSession()

// Stop recording
SessionReplaySDK.stopSession()

// Check status
if SessionReplaySDK.isRecording {
    print("Recording in progress...")
}
```

### 4. Track Screens (SwiftUI)

```swift
struct HomeView: View {
    var body: some View {
        NavigationView {
            // Your content
        }
        .trackScreen("HomeScreen")
    }
}
```

### 5. Custom Logging

```swift
SessionReplaySDK.debug("Debug: User opened settings")
SessionReplaySDK.info("Info: Purchase completed")
SessionReplaySDK.warning("Warning: Low storage")
SessionReplaySDK.error("Error: Network timeout")
```

### 6. Upload Sessions

```swift
// Configure endpoint
SessionReplaySDK.configureUpload(
    baseURL: URL(string: "https://api.yourserver.com/sessions")!,
    apiKey: "your-api-key"
)

// Upload specific session
SessionReplaySDK.uploadSession(sessionId: "abc-123") { result in
    switch result {
    case .success(let response):
        print("Uploaded: \(response.sessionId)")
    case .failure(let error):
        print("Failed: \(error)")
    }
}

// Upload all sessions
SessionReplaySDK.uploadAllSessions { results in
    let successful = results.filter { $0.1.isSuccess }.count
    print("Uploaded \(successful)/\(results.count) sessions")
}
```

## Configuration

### Video (SessionReplayConfig)

| Option | Default | Description |
|--------|---------|-------------|
| `enableVideoRecording` | `true` | Enable video recording (false for logs-only mode) |
| `captureFrameRate` | `1` | Frames per second (1-30) |
| `jpegCompressionQuality` | `0.3` | JPEG quality (0.0-1.0) |
| `captureScale` | `1.0` | Resolution scale (0.25-1.0) |
| `videoBitrate` | `75,000` | H.264 bitrate in bps |
| `captureTouches` | `true` | Record touch events |
| `showTouchIndicators` | `true` | Draw touch dots on video |
| `maskSensitiveViews` | `true` | Mask marked sensitive views |
| `sensitiveViewMaskColor` | `.gray` | Color for masked areas |
| `autoMaskTextFields` | `true` | Auto-mask text inputs |
| `autoMaskSecureTextFields` | `true` | Auto-mask password fields |
| `autoMaskViewClasses` | `[]` | Custom classes to auto-mask |
| `maxStorageSize` | `50MB` | Max local storage |
| `storageDirectory` | Documents | Custom storage location |

### Auto Start/Stop (SessionReplayConfig)

| Option | Default | Description |
|--------|---------|-------------|
| `autoStartOnLaunch` | `false` | Start recording on app launch |
| `autoStopOnBackground` | `true` | Stop when app enters background |
| `autoStopOnTerminate` | `true` | Emergency save on terminate |
| `enableCrashRecovery` | `true` | Save checkpoints periodically |
| `crashRecoveryInterval` | `5.0` | Seconds between checkpoints |
| `debugLogging` | `true` | Print debug logs to console |

### Logging (SessionLoggerConfig)

| Option | Default | Description |
|--------|---------|-------------|
| `captureConsoleLogs` | `true` | Capture stdout/stderr |
| `captureNetworkRequests` | `true` | Intercept URLSession |
| `minimumLogLevel` | `.debug` | Minimum capture level |
| `maxLogMessageLength` | `2000` | Truncate long messages |
| `maxBodySize` | `100KB` | Max request/response body |
| `redactedHeaders` | `[auth, cookie...]` | Headers to redact |
| `excludedURLPatterns` | `[]` | URL regex patterns to skip |
| `logSanitizer` | `nil` | Custom sanitization closure |
| `excludeSDKLogs` | `true` | Exclude SDK internal logs from session data |

### Upload (SessionUploadConfig)

| Option | Default | Description |
|--------|---------|-------------|
| `baseURL` | Required | Your upload endpoint |
| `apiKey` | `nil` | Bearer token auth |
| `additionalHeaders` | `[:]` | Custom headers |
| `maxRetries` | `3` | Retry on failure |
| `timeoutInterval` | `120s` | Request timeout |
| `deleteAfterUpload` | `false` | Remove local files |

## App Group Support

Share session data between your main app and extensions:

```swift
// Configure with App Group
SessionReplaySDK.configureWithAppGroup(
    "group.com.yourcompany.yourapp",
    videoConfig: config,
    logConfig: logConfig
)

// Or manually set storage directory
var config = SessionReplayConfig()
if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.yourapp") {
    config.storageDirectory = containerURL.appendingPathComponent("SessionReplays", isDirectory: true)
}
SessionReplaySDK.configure(videoConfig: config)
```

## User Identification

Attach user info to sessions for easier debugging:

```swift
// Simple identification
SessionReplaySDK.identifyUser(
    userId: "user_123",
    email: "user@example.com",
    name: "John Doe"
)

// With additional custom data
SessionReplaySDK.identifyUser(
    userId: "cashier_456",
    email: "cashier@foodics.com",
    additionalInfo: [
        "branchId": "branch_123",
        "role": "cashier",
        "shiftId": "shift_789"
    ]
)

// Set individual values
SessionReplaySDK.setUserInfo(key: "subscriptionTier", value: "premium")

// Clear on logout
SessionReplaySDK.clearUserInfo()

// Access current info
let currentUser = SessionReplaySDK.userInfo
```

User info is saved in both `metadata.userInfo` and root `userInfo` in the session JSON.

## Crash Recovery

The SDK automatically saves session checkpoints:

```swift
var config = SessionReplayConfig()
config.enableCrashRecovery = true      // Enable checkpoints
config.crashRecoveryInterval = 3.0     // Save every 3 seconds

SessionReplaySDK.configure(videoConfig: config)

// Check for incomplete sessions after app restart
let incompleteSessions = SessionReplaySDK.recoverIncompleteSessions()
for sessionId in incompleteSessions {
    print("Found incomplete session: \(sessionId)")
    // Video segments may be available even if session didn't complete
}
```

## Session Data Format

```json
{
  "sessionId": "550e8400-e29b-41d4-a716-446655440000",
  "startTime": "2025-01-27T10:30:00Z",
  "endTime": "2025-01-27T10:35:00Z",
  "durationMs": 300000,
  "frameCount": 3000,
  "videoSegments": ["session_segment0.mp4"],
  "userInfo": {
    "userId": "user_123",
    "email": "user@example.com",
    "branchId": "branch_456"
  },
  "touches": [
    {"timestamp": 1500, "location": {"x": 200, "y": 400}, "phase": 0}
  ],
  "logs": [
    {"timestamp": 2000, "level": "info", "message": "Button tapped", "source": "stdout"}
  ],
  "networkRequests": [
    {"timestamp": 3000, "method": "GET", "url": "https://api.example.com/data", "statusCode": 200, "duration": 150}
  ],
  "screenTransitions": [
    {"timestamp": 0, "screenName": "HomeScreen"}
  ],
  "metadata": {
    "appVersion": "1.0.0",
    "osVersion": "17.0",
    "deviceModel": "iPhone15,2",
    "locale": "en_US",
    "userInfo": {
      "userId": "user_123",
      "email": "user@example.com"
    }
  }
}
```

## Built-in Components

### SwiftUI

```swift
// Recording controls
RecordingControlView()

// Sessions list with upload
SessionsListView()

// Activity timeline (live during recording)
LiveActivityView()

// Activity timeline (for completed sessions)
ActivityTimelineView(session: selectedSession)

// Session player
SessionReplayViewer(session: selectedSession)

// Screen tracking modifier
.trackScreen("ScreenName")

// Touch indicators overlay
.withTouchIndicators()

// Mark sensitive content
.sensitiveContent()
```

### UIKit

```swift
// Base view controller with tracking
class MyVC: SessionReplayViewController {
    override var screenName: String { "MyScreen" }
}

// Debug view controller
let debugVC = SessionReplayDebugViewController()
present(debugVC, animated: true)

// Mark sensitive views
passwordField.markAsSensitive()
```

## Network Capture

The SDK captures all URLSession-based network requests, including:

- Direct URLSession usage
- Alamofire (including custom sessions with SSL pinning)
- FNetwork and other URLSession-based libraries

No additional configuration needed—network capture works automatically.

## Upload API

The SDK sends multipart form data:

| Field | Type | Description |
|-------|------|-------------|
| `sessionId` | String | Session identifier |
| `video` | File | MP4 video file |
| `metadata` | File | JSON metadata file |

**Expected Response:**
```json
{
  "sessionId": "...",
  "videoURL": "https://...",
  "metadataURL": "https://...",
  "message": "Success"
}
```

**Testing Upload:**
- Use [webhook.site](https://webhook.site) for instant testing
- Use [requestbin.com](https://requestbin.com) as alternative
- Or `https://postman-echo.com/post` for echo testing

## Privacy & Security

### Sensitive Data Masking

The SDK automatically masks sensitive content in screen recordings:

**Automatic Masking (enabled by default):**
- Secure text fields (password inputs)
- Regular text fields and text views
- Views marked with `markAsSensitive()` or `.sensitiveContent()`

**Configuration Options:**
```swift
var config = SessionReplayConfig()
config.maskSensitiveViews = true          // Enable/disable masking
config.sensitiveViewMaskColor = .gray     // Mask color
config.autoMaskTextFields = true          // Auto-mask UITextField/UITextView
config.autoMaskSecureTextFields = true    // Auto-mask password fields
config.autoMaskViewClasses = ["CreditCardView"]  // Custom classes to mask
```

**Manual Masking - UIKit:**
```swift
// Mark any UIView as sensitive
passwordField.markAsSensitive()
creditCardView.markAsSensitive()

// Check if view is marked
if myView.isSensitive { ... }
```

**Manual Masking - SwiftUI:**
```swift
// Mark any SwiftUI view as sensitive
SecretDataView()
    .sensitiveContent()

// With custom mask color
PaymentForm()
    .sensitiveContent(maskColor: .black)
```

**Opting a view out of automatic masking:**

When `autoMaskTextFields` is on, a single field can be kept visible without
turning masking off app-wide:

```swift
// SwiftUI
TextField("Search products", text: $query)
    .unmaskedContent()

// UIKit
searchField.markAsUnmasked()
```

The opt-out applies by frame, so marking a container exposes the auto-masked
fields inside it. Two rules always win over it:

- Views marked `markAsSensitive()` / `.sensitiveContent()` stay masked.
- **Secure text fields (`isSecureTextEntry`) are never exposed by an opt-out**,
  even when nested inside an unmasked container. Use `autoMaskSecureTextFields`
  if you genuinely need to disable password masking.

### Additional Privacy Features

- **Header Redaction**: Authorization, Cookie, API keys auto-redacted from network logs
- **URL Exclusion**: Regex patterns to exclude specific endpoints
- **Log Sanitization**: Custom closure for PII removal
- **Local-First**: All data stored locally, upload is opt-in
- **No Dependencies**: Pure Swift, no third-party tracking code

## Architecture

```
SessionReplaySDK/
├── Core/
│   ├── Models.swift              # Data structures
│   ├── SessionReplayManager.swift # Main controller
│   └── VideoWriter.swift         # H.264 encoding
├── Logging/
│   ├── SessionLogger.swift       # Console capture
│   └── NetworkInterceptor.swift  # URL monitoring
├── Upload/
│   └── SessionUploader.swift     # Cloud upload
├── Integration/
│   ├── SwiftUIIntegration.swift  # SwiftUI support
│   └── UIKitIntegration.swift    # UIKit support
└── SessionReplaySDK.swift        # Public facade
```

## Changelog

### Version 0.2.2
- **Security fix — an unmask opt-out can no longer expose a password field.** `markAsUnmasked()` / `.unmaskedContent()` exempted a view from *all* automatic masking, including `isSecureTextEntry` fields, so opting a container out (e.g. a whole form section) silently revealed any password field inside it in the recorded video. Secure text entry is now never exposed by an opt-out; `autoMaskSecureTextFields` is still honoured as an explicit global setting.
- **Fix: `redactedHeaders` is now genuinely case-insensitive**, as documented. Only the incoming header name was lower-cased, not the configured set, so a config of `["Authorization"]` redacted nothing and the token was written into the captured session log. Both sides are normalised now.
- **Tests**: added a `SessionReplaySDKTests` target covering masking (auto-mask, opt-out precedence, secure-field guarantees, frame geometry) and capture gating (nothing captured without an active session, header redaction, body truncation).
- **CI**: GitHub Actions workflow builds and tests on an iOS simulator for every pull request, plus a device-architecture build.

### Version 0.2.1
- **Touch capture no longer swizzles `UIWindow.sendEvent(_:)`**: touches are now observed by a passive, never-recognizing gesture recognizer attached to each window. The swizzle placed the SDK on the call stack of every touch dispatch, so any `NSException` raised by UIKit or by app code during touch handling (e.g. the iOS 26 TextKit 2 crash in `-[UITextField _visualSelectionRangeForExtent:…]` when dragging a text-selection handle) was misattributed to `SessionReplayManager.sr_sendEvent` in crash reporters. The SDK no longer wraps UIKit's event pipeline at all.
- **Nothing runs without an active session**: touch observers are attached in `startSession()` and removed in `stopSession()` (previously the swizzle was installed at `configure()` and stayed active whether or not a session was recording). Network response-body buffering is now skipped when no session is capturing. Frame capture, console capture and the crash-recovery timer were already session-scoped.
- **Per-view opt-out from auto-masking**: `.unmaskedContent()` (SwiftUI) and `UIView.markAsUnmasked()` (UIKit) keep a text field visible in the replay while `autoMaskTextFields` stays on for everything else. Explicit `sensitiveContent()` / `markAsSensitive()` still wins.

### Version 0.2.0
- **User Identification**: New `identifyUser()` and `setUserInfo()` APIs to attach user data to sessions
- **App Group Support**: Configure custom storage directory for sharing data between app and extensions
- **Auto Start/Stop**: New config options for automatic session lifecycle management
- **Crash Recovery**: Periodic checkpoints to recover sessions after crashes
- **Network Capture Improvements**: Works with all URLSession-based networking including Alamofire with SSL pinning
- **Activity Timeline Views**: New `LiveActivityView` and `ActivityTimelineView` SwiftUI components
- **Debug Logging Control**: New `debugLogging` config to reduce console noise in production
- **Removed Verbose Touch Logging**: Touch began/ended events no longer spam the console

### Version 0.1.0
- Initial release
- Video recording with H.264 encoding
- Touch event capture and visualization
- Console log interception
- Network request monitoring
- SwiftUI and UIKit integration
- Cloud upload support

## Contributing

We welcome contributions!

1. Fork the repository
2. Create feature branch: `git checkout -b feature/amazing`
3. Commit changes: `git commit -m 'Add amazing feature'`
4. Push: `git push origin feature/amazing`
5. Open Pull Request

Please include tests and update documentation.

## Requirements

- iOS 15.0+
- Swift 5.9+
- Xcode 15.0+


## Support

- **Issues**: [GitHub Issues](https://github.com/AlmoutasemNabil/SessionReplaySDK/issues)
- **Discussions**: [GitHub Discussions](https://github.com/AlmoutasemNabil/SessionReplaySDK/discussions)

---

## 📄 License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

---

<div align="center">

**Made with ❤️ by [AlmoutasemNabil](https://github.com/AlmoutasemNabil)**

© 2026 AlmoutasemNabil. All rights reserved.

⭐ **Star this repo if you find it helpful!**

</div>
