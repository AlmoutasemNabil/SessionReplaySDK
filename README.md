# SessionReplaySDK

A comprehensive iOS SDK for recording session replays with video capture, console log capture, and network request interception. Perfect for debugging, analytics, and user experience research.

## Features

- **Video Capture**: Record screen content at configurable frame rates with H.264 compression
- **Touch Tracking**: Capture and visualize touch events
- **Console Log Capture**: Intercept stdout/stderr with log level classification
- **Network Request Capture**: Automatic URLSession interception with request/response logging
- **Local Storage**: Save sessions locally with configurable size limits
- **Cloud Upload**: Upload video and JSON metadata to your backend
- **SwiftUI & UIKit Support**: View modifiers, components, and base classes

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourorg/SessionReplaySDK.git", from: "1.0.0")
]
```

Or in Xcode: File > Add Packages > Enter the repository URL

## Quick Start

### 1. Configure on App Launch

```swift
import SessionReplaySDK

@main
struct MyApp: App {
    init() {
        // Configure video capture
        var videoConfig = SessionReplayConfig()
        videoConfig.captureFrameRate = 1
        videoConfig.captureScale = 0.75

        // Configure logging
        var logConfig = SessionLoggerConfig()
        logConfig.captureConsoleLogs = true
        logConfig.captureNetworkRequests = true

        // Initialize SDK
        SessionReplaySDK.configure(
            videoConfig: videoConfig,
            logConfig: logConfig
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

// Check if recording
if SessionReplaySDK.isRecording {
    print("Currently recording")
}
```

### 3. Upload Sessions

```swift
// Configure upload endpoint
SessionReplaySDK.configureUpload(
    baseURL: URL(string: "https://api.yourbackend.com/sessions")!,
    apiKey: "your-api-key"
)

// Upload a specific session
SessionReplaySDK.uploadSession(sessionId: "session-id") { result in
    switch result {
    case .success(let response):
        print("Uploaded: \(response.videoURL ?? "")")
    case .failure(let error):
        print("Failed: \(error)")
    }
}

// Upload all pending sessions
SessionReplaySDK.uploadAllSessions { results in
    print("Uploaded \(results.count) sessions")
}
```

### 4. Track Screens (SwiftUI)

```swift
struct HomeView: View {
    var body: some View {
        VStack {
            // Your content
        }
        .trackScreen("HomeScreen")  // Adds screen transition to session
    }
}
```

### 5. Custom Logging

```swift
// Log messages to the session
SessionReplaySDK.debug("Debug message")
SessionReplaySDK.info("Info message")
SessionReplaySDK.warning("Warning message")
SessionReplaySDK.error("Error message")
```

## Configuration Options

### Video Capture (SessionReplayConfig)

| Option | Default | Description |
|--------|---------|-------------|
| `captureFrameRate` | `1` | Frames per second to capture |
| `jpegCompressionQuality` | `0.3` | JPEG quality (0.0 - 1.0) |
| `captureScale` | `1.0` | Scale factor (0.5 = half resolution) |
| `videoBitrate` | `75,000` | Video bitrate in bps |
| `maxStorageSize` | `50MB` | Maximum local storage |
| `captureTouches` | `true` | Capture touch events |
| `showTouchIndicators` | `true` | Draw touch indicators on video |

### Logging (SessionLoggerConfig)

| Option | Default | Description |
|--------|---------|-------------|
| `captureConsoleLogs` | `true` | Capture stdout/stderr |
| `captureNetworkRequests` | `true` | Intercept network calls |
| `minimumLogLevel` | `.debug` | Minimum level to capture |
| `maxLogMessageLength` | `2000` | Truncate long messages |
| `maxBodySize` | `100KB` | Max request/response body |
| `redactedHeaders` | `[auth, cookie, ...]` | Headers to redact |
| `excludedURLPatterns` | `[]` | URLs to skip (regex) |

### Upload (SessionUploadConfig)

| Option | Default | Description |
|--------|---------|-------------|
| `baseURL` | - | Upload endpoint URL |
| `apiKey` | `nil` | Authentication token |
| `maxRetries` | `3` | Retry attempts on failure |
| `timeoutInterval` | `120s` | Upload timeout |
| `deleteAfterUpload` | `false` | Remove local files after upload |

## Upload API

The SDK uploads sessions as multipart form data with the following fields:

- `sessionId`: String - Unique session identifier
- `video`: File - MP4 video file
- `metadata`: File - JSON metadata file

### Expected Response

```json
{
  "sessionId": "...",
  "videoURL": "https://...",
  "metadataURL": "https://...",
  "message": "Upload successful"
}
```

## Session JSON Structure

```json
{
  "sessionId": "550e8400-...",
  "startTime": "2025-01-27T10:30:00Z",
  "endTime": "2025-01-27T10:32:45Z",
  "durationMs": 165000,
  "videoSegments": ["session_segment0.mp4"],
  "metadata": {
    "appVersion": "2.5.0",
    "osVersion": "17.2",
    "deviceModel": "iPhone15,2"
  },
  "touches": [...],
  "logs": [...],
  "networkRequests": [...],
  "screenTransitions": [...]
}
```

## SwiftUI Components

### RecordingControlView

A ready-to-use recording control widget:

```swift
RecordingControlView()
```

### SessionsListView

List and manage recorded sessions:

```swift
SessionsListView()
```

### SessionReplayViewer

Play back a recorded session:

```swift
SessionReplayViewer(session: session)
```

## UIKit Integration

### Base View Controller

```swift
class MyViewController: SessionReplayViewController {
    override var screenName: String {
        return "CustomScreenName"
    }
}
```

### Mark Sensitive Views

```swift
passwordField.markAsSensitive()
```

### Debug View Controller

```swift
let debugVC = SessionReplayDebugViewController()
present(debugVC, animated: true)
```

## Privacy & Security

- **Sensitive Headers**: Authorization, Cookie, and API key headers are automatically redacted
- **Custom Redaction**: Use `logSanitizer` closure for app-specific redaction
- **URL Exclusion**: Exclude analytics/SDK endpoints from capture
- **Sensitive Views**: Mark views as sensitive to exclude from capture

## Best Practices

1. **Start recording selectively**: Don't record everything, focus on key user flows
2. **Configure exclusions**: Exclude your own backend URLs to prevent infinite loops
3. **Set reasonable limits**: Use `maxStorageSize` to prevent disk space issues
4. **Handle upload failures**: Implement retry logic and offline queuing
5. **Respect user privacy**: Always get consent before recording

## Requirements

- iOS 15.0+
- Swift 5.9+
- Xcode 15.0+

## License

MIT License - see LICENSE file for details.
