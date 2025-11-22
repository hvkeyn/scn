# SCN - Secure Connection Network

Simplified application for secure file and message sharing over local network.

## Description

SCN is a cross-platform application that allows you to securely exchange files and messages between devices on a local network without requiring an internet connection.

## Features

- ✅ **Flutter/Dart only** - No Rust dependencies
- ✅ **Simple build** - `flutter build windows`
- ✅ **HTTP server** - Dart-based (shelf)
- ✅ **UDP Multicast Discovery** - Automatic device discovery
- ✅ **Chat** - Real-time message exchange
- ✅ **File transfer** - Send and receive files
- ✅ **Beautiful UI** - Modern interface with SCN logo

## Quick Start

### Install Dependencies

```bash
flutter pub get
```

### Run in Development Mode

```bash
flutter run -d windows
```

### Build Release

```bash
# From project root directory
.\build.ps1 -Project scn -Platform windows -BuildType zip
```

Result will be in `scn-release/` folder.

## Project Structure

```
lib/
├── main.dart              - Application entry point
├── services/              - Services
│   ├── app_service.dart           - Main coordination service
│   ├── http_server_service.dart   - HTTP server for receiving
│   ├── http_client_service.dart   - HTTP client for sending
│   ├── discovery_service.dart     - UDP multicast discovery
│   └── file_service.dart          - File operations
├── pages/                 - UI pages
│   ├── home_page.dart            - Main page
│   └── tabs/                     - Tabs
│       ├── receive_tab.dart      - Receive files
│       ├── send_tab.dart         - Send files
│       ├── chat_tab.dart         - Chat
│       └── settings_tab.dart     - Settings
├── providers/             - State management (Provider)
│   ├── device_provider.dart      - Device list
│   ├── receive_provider.dart     - Receive state
│   ├── send_provider.dart        - Send state
│   └── chat_provider.dart       - Chat state
├── models/                - Data models
│   ├── device.dart              - Device model
│   ├── file_info.dart           - File information
│   ├── session.dart             - Transfer session
│   ├── chat_message.dart        - Chat message
│   └── multicast_dto.dart       - Multicast DTO
└── widgets/               - Reusable widgets
    └── scn_logo.dart            - SCN logo
```

## Dependencies

Main dependencies:

- `shelf` - HTTP server
- `http` - HTTP client
- `multicast_dns` - Device discovery
- `provider` - State management
- `file_picker` - File selection
- `path_provider` - Directory paths
- `crypto` - Cryptography
- `uuid` - UUID generation

Full list in `pubspec.yaml`.

## API

### HTTP Endpoints

- `GET /api/info` - Device information
- `POST /api/register` - Device registration (response to multicast)
- `POST /api/session` - Create file transfer session
- `POST /api/accept` - Accept files for receiving
- `POST /api/upload` - Upload file
- `POST /api/chat` - Send message

### UDP Multicast

- Port: 53317
- Group: 224.0.0.167
- Protocol: JSON over UDP

## Development

### Requirements

- Flutter SDK 3.25.0+
- Dart 3.9.0+

### Testing

```bash
flutter test
```

### Code Analysis

```bash
flutter analyze
```

## Version

Current version: **1.0.0**

## License

Based on LocalSend, simplified version.
