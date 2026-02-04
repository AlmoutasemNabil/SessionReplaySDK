# SessionReplaySDK

<p align="center">
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
| **Network Tracking** | Monitor all HTTP/HTTPS requests with full details |
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
    .package(url: "https://github.com/AlmoutasemNabil/SessionReplaySDK", from: "1.0.0")
]
```

## Quick Start

### 1. Configure on App Launch

```swift
import SessionReplaySDK

@main
struct MyApp: App {
    init() {
        SessionReplaySDK.configure(
            videoConfig: SessionReplayConfig(
                captureFrameRate: 10,
                jpegCompressionQuality: 0.7,
                captureScale: 0.5
            ),
            logConfig: SessionLoggerConfig(
                captureConsoleLogs: true,
                captureNetworkRequests: true
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### 2. Start/Stop Recording

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

### 3. Track Screens (SwiftUI)

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

### 4. Custom Logging

```swift
SessionReplaySDK.debug("Debug: User opened settings")
SessionReplaySDK.info("Info: Purchase completed")
SessionReplaySDK.warning("Warning: Low storage")
SessionReplaySDK.error("Error: Network timeout")
```

### 5. Upload Sessions

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
| `maxSessionDuration` | `300s` | Auto-stop after duration |

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

### Upload (SessionUploadConfig)

| Option | Default | Description |
|--------|---------|-------------|
| `baseURL` | Required | Your upload endpoint |
| `apiKey` | `nil` | Bearer token auth |
| `additionalHeaders` | `[:]` | Custom headers |
| `maxRetries` | `3` | Retry on failure |
| `timeoutInterval` | `120s` | Request timeout |
| `deleteAfterUpload` | `false` | Remove local files |

## Session Data Format

```json
{
  "sessionId": "550e8400-e29b-41d4-a716-446655440000",
  "startTime": "2025-01-27T10:30:00Z",
  "endTime": "2025-01-27T10:35:00Z",
  "durationMs": 300000,
  "frameCount": 3000,
  "videoSegments": ["session_segment0.mp4"],
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
    "locale": "en_US"
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

// Session player
SessionReplayViewer(session: selectedSession)

// Screen tracking modifier
.trackScreen("ScreenName")

// Touch indicators overlay
.withTouchIndicators()
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
