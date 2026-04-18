# Pull Request: Remote Desktop (PR #1 — foundation)

## Summary

Initial implementation of a built-in **Remote Desktop** feature, similar in spirit
to RustDesk: any SCN host on the LAN can publish its screen (and optionally
system audio) over WebRTC, while a viewer device on the same network can
display the stream and disconnect at will. The feature is fully integrated
into the existing SCN UI: a new **Remote** tab, a **Remote Desktop** section
in Settings, and an action item in `PeerTile`.

This PR delivers a **viewer-only** experience (no remote control yet).
Native input injection and the ability for the viewer to drive the host with
mouse and keyboard arrives in **PR #2**. The Total Commander–style file
manager is **PR #3**, and WAN signalling + adaptive optimizations is
**PR #4**.

## New Features

### Remote Desktop hosting

- WebRTC screen + audio capture using `flutter_webrtc.getDisplayMedia()`.
- New per-device on/off switch, plus auto-generated permanent password.
- Three access modes:
  - **Password only** — RustDesk-like flow.
  - **Prompt only** — viewer must be approved manually each session.
  - **Password or prompt** — either path is accepted (default).
- Trusted-peer list (auto-accept without prompt) wired into the data model
  ready to be exposed in PR #2.
- Configurable defaults: bitrate cap (1.5–25 Mbps or auto), target FPS
  (15–60 or auto), preferred codec (H.264/VP8/VP9/AV1/auto).
- Live session list — host can disconnect any viewer at any time.

### Remote Desktop client (viewer)

- Manual host/port/password entry **and** one-click connect from any LAN peer
  discovered through the existing mDNS service.
- Full-screen viewer with adaptive `RTCVideoView`.
- Live performance overlay (toggleable): bitrate, FPS, RTT, resolution.
- Clean disconnect / kick semantics.

### Permission flow

- Per-app `RemoteDesktopPermissionListener` widget mounted at app root.
  When the host receives a request that needs approval, a 30-second-timeout
  dialog appears with: viewer alias, viewer IP, requested mode, control
  request flag.
- Approval / rejection results travel back to the host service via a stream
  + completer.

### LAN signalling

- Three new HTTP endpoints exposed by the existing `HttpServerService`:
  - `POST /api/rd/request` — handshake; returns session id + token + WS path.
  - `POST /api/rd/end` — graceful close (best-effort).
  - `GET  /api/rd/ws`    — WebSocket signalling channel for SDP/ICE.
- Reuses the LAN port that already listens for file/chat traffic, so no
  firewall/NAT changes needed.

## Files Added

```
lib/models/remote_desktop_models.dart
lib/services/remote_desktop/remote_desktop_protocol.dart
lib/services/remote_desktop/remote_desktop_host_service.dart
lib/services/remote_desktop/remote_desktop_client_service.dart
lib/pages/remote_desktop_page.dart
lib/pages/remote_desktop_viewer_page.dart
lib/widgets/remote_desktop_permission_dialog.dart
lib/widgets/remote_desktop_permission_listener.dart
PULL_REQUEST_REMOTE_DESKTOP.md
```

## Files Modified

```
lib/models/remote_peer.dart            — NetworkSettings now nests RemoteDesktopSettings
lib/providers/remote_peer_provider.dart — RD setter helpers + persistence
lib/services/http_server_service.dart   — RD HTTP routes + WS handler
lib/services/app_service.dart           — owns + lifecycles the RD host service
lib/main.dart                           — provides RD service + wraps app in listener
lib/pages/home_page.dart                — adds Remote tab to nav rail / bottom bar
lib/pages/tabs/settings_tab.dart        — new Remote Desktop settings card
lib/widgets/peer_tile.dart              — onRemoteControl popup item
```

## Architecture Notes

```
            Viewer (client)                                Host
+---------------------------------+               +-------------------------+
| RemoteDesktopClientService      |               | RemoteDesktopHostService|
|  - HTTP POST /api/rd/request    |==REST=>       |  - validates pwd/prompt |
|  - WebSocket /api/rd/ws         |==WS=>         |  - spawns RTCPeerConn   |
|  - createOffer ─ via WS         |               |  - getDisplayMedia()    |
|  - onTrack -> RTCVideoRenderer  |<==RTP video===|  - addTrack(video,audio)|
|  - DataChannel 'scn-rd-input'   |==DC===========|  - awaits input events  |
+---------------------------------+   (PR #2)     +-------------------------+
```

- **Single permanent host service** (`RemoteDesktopHostService`) lives inside
  `AppService`, wired into the existing HTTP server through the new RD
  routes. Settings updates propagate via the same listener already used for
  mesh/network changes.
- **Per-attempt client service** (`RemoteDesktopClientService`) is created by
  the viewer page and disposed on close.
- WebRTC peer connections currently use Google STUN servers; PR #4 will
  surface STUN/TURN config from `NetworkSettings.stunServers`/`turnServers`
  (already present) for WAN scenarios.
- Quality control already piped through a `qualityChange` signal (bitrate +
  FPS); the UI hook is in place but the in-call slider is deferred to PR #4.

## Limitations of this PR

1. **No remote control yet.** `wantsControl` is honoured in the protocol but
   input events received by the host are logged-only. PR #2 wires Win32
   `SendInput` via `dart:ffi`, plus stubs for macOS (`CGEventPost`) and
   Linux (`xdotool` / uinput).
2. **LAN only.** Signalling assumes both ends can reach each other directly.
   PR #4 reuses the existing `signaling_server.dart` for WAN bootstrap.
3. **Adaptive bitrate is single-track** (no simulcast / SVC). Default values
   apply at session start; mid-session quality slider arrives in PR #4.
4. **Audio capture depends on the platform.** On Windows it uses WASAPI
   loopback through `flutter_webrtc`; on macOS and Linux it currently falls
   back to no-audio if the platform refuses the request.
5. **Stats are coarse.** The 2-second window gives bitrates within ±10%; in
   PR #4 we'll switch to a delta-based calculation using `prevReports`.
6. **Multi-monitor:** captures the primary display only.

## How to Use

### Becoming a host

1. `Settings → Remote Desktop → Allow remote desktop` → ON.
2. Copy the auto-generated password (or change the access mode to
   "Prompt only" if you don't want password access).
3. Optional: choose default bitrate/FPS/codec, enable system audio.

### Connecting as a viewer

1. Open the **Remote** tab.
2. Either pick a discovered LAN device and click **Connect**, or fill in
   host/port/password manually.
3. The host either sees a permission dialog (and approves) or the session
   starts immediately if the password matched / the device is trusted.
4. Click the bar-chart icon in the viewer toolbar to toggle the live stats
   overlay; click the door icon to disconnect.

## Manual Testing Plan

- [ ] On a single Windows machine, run two instances with `--test-mode 0`
      and `--test-mode 1` (existing test rig). Verify discovery works.
- [ ] Enable hosting on instance A, connect from instance B, observe the
      permission dialog if prompt-mode and the live preview if accepted.
- [ ] Toggle "View-only by default" and ensure the permission dialog
      reflects the request mode correctly.
- [ ] Change bitrate/FPS in settings, reconnect, verify the values are
      applied (visible via the stats overlay).
- [ ] Disconnect from the host card and confirm the viewer page reports
      "Closed".
- [ ] Stop the host (toggle off) mid-session and verify the viewer
      gracefully closes.

## Build status

- `flutter pub get` — OK.
- `flutter analyze` — 74 issues; **0 errors** (warnings/lints are pre-existing
  `print()` calls plus a few `unused_field`/`unused_import` from earlier
  iterations of the codebase).
- `flutter build windows --debug` — OK
  (`build\windows\x64\runner\Debug\scn.exe`).

## Roadmap (next PRs)

- **PR #2** — Native input injection (Windows FFI), control toolbar,
  on-screen keyboard helpers, copy/paste sync.
- **PR #3** — Total Commander-style dual-pane file manager, with chunked
  binary transfer over a dedicated DataChannel and resumable uploads.
- **PR #4** — WAN signalling integration, adaptive bitrate slider, codec
  preference enforcement (SDP munging), macOS / Linux input back-ends.
