# SCN - Secure Connection Network

<div align="center">
  <h3>Secure file and message sharing over local network</h3>
  <p>Cross-platform application for transferring files and chatting between devices without internet</p>
</div>

## About

SCN (Secure Connection Network) is a simplified version of an application for secure file and message sharing between devices over a local network. Unlike other solutions, SCN does not require an internet connection or external servers - all data is transmitted directly between devices.

## Features

- ✅ **Secure file sharing** - Transfer files between devices on local network
- ✅ **Real-time chat** - Exchange text messages between devices
- ✅ **Automatic device discovery** - UDP multicast for finding devices on network
- ✅ **Secure mesh network** - Connect remote peers over the internet via signaling + WebRTC foundation
- ✅ **TURN-ready fallback** - Relay path for symmetric NAT, CGNAT and mobile networks
- ✅ **Simple architecture** - Flutter/Dart only, no complex dependencies
- ✅ **Cross-platform** - Windows, Linux, macOS (in development)
- ✅ **Privacy** - Works without external servers, all data transmitted directly

## Technologies

- **Flutter** - UI and cross-platform development
- **Dart** - All application logic
- **shelf** - HTTP server for receiving files
- **multicast_dns** - Device discovery on network
- **Provider** - State management
- **WSL** - Windows Subsystem for Linux (for building Linux on Windows)

## Installation and Setup

### Requirements

- Flutter SDK 3.25.0 or higher
- **Windows 10+** (for Windows builds)
- **Linux** (Ubuntu 20.04+, Debian 11+, or similar) - for Linux builds
- **WSL** (Windows Subsystem for Linux) - for building Linux on Windows

### Building from Source

1. Clone the repository:
```bash
git clone https://github.com/hvkeyn/scn.git
cd scn
```

2. Navigate to project directory:
```bash
cd scn
```

3. Install dependencies:
```bash
flutter pub get
```

4. Build the project:
```bash
# Windows
flutter build windows

# Or use build script (from project root)
cd ..
.\build.ps1 -Platform windows

# Linux (native or WSL)
chmod +x build.sh
./build.sh

# Note: For Windows, you need Ubuntu WSL. See LINUX_BUILD.md for details.

# Or from scn directory
cd scn
flutter build linux --release
```

### Pre-built Releases

**Windows release** is located in `scn-release/` folder:

```
scn-release/
├── scn.exe                 - Main executable
├── flutter_windows.dll     - Flutter engine
├── data/                   - Application data
│   ├── app.so             - Compiled code
│   ├── icudtl.dat         - ICU data
│   └── flutter_assets/    - Resources
└── README.txt             - Instructions
```

**Linux release** is located in `scn-release-linux/` folder:

```
scn-release-linux/
├── scn                     - Main executable
├── lib/                    - Application libraries
├── data/                   - Application data
│   └── flutter_assets/   - Resources
└── README.txt             - Instructions
```

**Run:**
- **Windows:** Double-click `scn.exe` or run: `.\scn.exe`
- **Linux:** Make executable: `chmod +x scn`, then run: `./scn`

## Usage

### Network Setup

For the application to work, you need to:

1. **Configure firewall:**
   - Allow incoming TCP/UDP connections on port 53317 (HTTP/Discovery)
   - Allow outgoing connectivity to signaling and TURN services
   - Allow outgoing TCP/UDP connections

2. **Disable AP Isolation:**
   - Make sure AP Isolation is disabled on your router
   - This is necessary for device discovery on network

3. **Set network as "Private":**
   - On Windows: configure network as "Private" (not "Public")

4. **For remote connections:**
   - Prefer invite tokens through signaling backend
   - Keep TURN available as standard fallback
   - Router port forwarding is optional and mainly helps legacy direct mode

### Main Features

- **Send files:** Select files and send them to another device
- **Receive files:** Receive files from other devices on network
- **Chat:** Exchange messages with devices on network
- **Settings:** Change device name, port and other parameters

## Project Structure

```
scn/
├── lib/
│   ├── main.dart              - Entry point
│   ├── services/              - Application services
│   │   ├── app_service.dart           - Main service
│   │   ├── http_server_service.dart   - HTTP server
│   │   ├── http_client_service.dart   - HTTP client
│   │   ├── discovery_service.dart     - Device discovery
│   │   ├── secure_channel_service.dart - WebSocket/TLS channel
│   │   ├── mesh_network_service.dart  - Mesh network
│   │   └── file_service.dart          - File operations
│   ├── pages/                 - Application pages
│   │   ├── home_page.dart            - Main page
│   │   └── tabs/                     - Tabs
│   │       ├── receive_tab.dart      - Receive files
│   │       ├── send_tab.dart         - Send files
│   │       ├── chat_tab.dart         - Chat
│   │       └── settings_tab.dart     - Settings
│   ├── providers/             - State management
│   │   ├── device_provider.dart      - Devices
│   │   ├── receive_provider.dart     - Receive state
│   │   ├── send_provider.dart        - Send state
│   │   ├── chat_provider.dart        - Chat state
│   │   └── remote_peer_provider.dart - Remote peers
│   ├── models/                - Data models
│   │   ├── device.dart              - Device model
│   │   ├── file_info.dart           - File information
│   │   ├── session.dart             - Transfer session
│   │   ├── chat_message.dart        - Chat message
│   │   ├── multicast_dto.dart       - Multicast data
│   │   └── remote_peer.dart         - Remote peer model
│   └── widgets/               - Widgets
│       ├── scn_logo.dart            - SCN logo
│       ├── add_peer_dialog.dart     - Add peer dialog
│       ├── invitation_card.dart     - Invitation card
│       └── peer_tile.dart           - Peer list tile
├── windows/                   - Windows configuration
├── linux/                     - Linux configuration
├── pubspec.yaml              - Dependencies
└── README.md                 - This file
```

## Protocol

SCN uses a simple HTTP-based protocol for data exchange:

### Local Network
- **Device discovery:** UDP multicast on port 53317
- **HTTP server:** TCP on port 53317 (default)
- **API endpoints:**
  - `GET /api/info` - Device information
  - `POST /api/register` - Device registration
  - `POST /api/session` - Create transfer session
  - `POST /api/accept` - Accept files
  - `POST /api/upload` - Upload file
  - `POST /api/chat` - Send message

### Secure Mesh Network
- **Secure channel:** WebSocket over TLS on port 53318 (default)
- **Mesh sync:** Automatic peer list propagation
- **Authentication:** Optional password protection
- **Message types:** handshake, peerList, invitation, data, ping/pong

## Development

### Running in Development Mode

**Windows:**
```bash
cd scn
flutter run -d windows
```

**Linux:**
```bash
cd scn
flutter run -d linux
```

### Testing

```bash
cd scn
flutter test
```

### Building Release

**Windows:**
```powershell
.\build.ps1 -Platform windows
```
Result will be in `scn-release/` folder.

**Linux (native or WSL):**
```bash
chmod +x build.sh
./build.sh
```
Result will be in `scn-release-linux/` folder.

**Linux on Windows (via WSL):**
```powershell
.\build.ps1 -Platform linux
```
The script will automatically detect and use Ubuntu WSL if available.

**Note:** For building Linux on Windows, you need **Ubuntu WSL** installed (not just docker-desktop). See `LINUX_BUILD.md` for detailed setup instructions.

## Compatibility

| Platform | Minimum Version | Status |
|----------|----------------|--------|
| Windows  | 10              | ✅ Supported |
| Linux    | Ubuntu 20.04+   | ✅ Supported |
| macOS    | -               | 🚧 In development |
| Android  | -               | 📋 Planned |
| iOS      | -               | 📋 Planned |

## Troubleshooting

### Devices can't see each other

1. Check that both devices are on the same network
2. Make sure AP Isolation is disabled on router
3. Check firewall settings
4. On Windows: set network as "Private"

### Files not transferring

1. Check that server is running (in settings)
2. Make sure port 53317 is not occupied by another application
3. Check application logs

### Slow transfer speed

1. Use 5 GHz Wi-Fi instead of 2.4 GHz
2. Make sure devices are on the same subnet
3. Check network load

## License

This project is based on [LocalSend](https://github.com/localsend/localsend) and uses a simplified architecture.

## Contributing

We welcome contributions to the project! If you want to help:

1. Create an issue to discuss changes
2. Fork the repository
3. Create a pull request with description of changes

## Version

Current version: **1.0.0+16**

## Contacts

- GitHub: https://github.com/hvkeyn/scn
- Issues: https://github.com/hvkeyn/scn/issues

---

<div align="center">
  <p>Made with ❤️ for secure file sharing</p>
</div>
