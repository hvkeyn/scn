# Pull Request: Remote Desktop (PR #2 — input control + Windows FFI injector)

## Summary

PR #2 turns the viewer-only remote desktop session from PR #1 into a full
**remotely controlled session**: the viewer can move the mouse, click,
scroll, type and even send `Ctrl + Alt + Del` to the host. The host
receives the events through a WebRTC DataChannel and synthesizes them on
the OS using a platform-specific input injector. A native **Windows
implementation** is provided via `SendInput` (FFI) and a logical/physical
key mapping table; macOS and Linux ship with safe stubs that will be
filled in PR #4 (and via uinput/CGEvent in their own platform PRs).

Compared with PR #1 the user experience now matches RustDesk: connect,
optionally toggle "Enable input forwarding" in the toolbar, and operate
the remote machine as if you were sitting in front of it.

## New / modified behavior

### Viewer side (`lib/pages/remote_desktop_viewer_page.dart`)

- New toolbar with:
  - **Input switch** (only enabled if the host granted full control).
  - **Keyboard capture** toggle (so the viewer can locally use shortcuts
    when needed).
  - **Send Ctrl + Alt + Del** button (sequenced key down/up events).
  - **Stats overlay** toggle and **Disconnect** button.
- Wraps the `RTCVideoView` in `MouseRegion` + `Listener` to capture
  mouse move, button down/up and scroll events.
- Wraps the entire video area in a `Focus` node with `onKeyEvent` to
  capture keyboard events when control is enabled.
- Coordinates are **normalized** to `0..1` against the video widget's
  current size, so the event remains correct regardless of resolution
  mismatch between viewer and host.
- Move events are throttled (delta < 0.001) to avoid flooding the data
  channel during high-frequency hovering.
- Modifier keys (`shift`, `ctrl`, `alt`, `meta`) are detected through
  `HardwareKeyboard.instance.logicalKeysPressed` and attached to every
  `RemoteInputEvent`.

### Host side input injection (`lib/services/remote_desktop/input_injector/`)

Introduces a small abstraction so each platform plugs in its own native
implementation without polluting the host service:

- `input_injector.dart` — abstract `InputInjector` with
  `setTargetSize`, `inject(RemoteInputEvent)` and `dispose()`.
- `input_injector_stub.dart` — no-op for unsupported platforms (web,
  unknown OS); reports `isAvailable = false`.
- `input_injector_native.dart` — selector that returns
  `WindowsInputInjector` on Windows and the stub elsewhere.
- `input_injector_windows.dart` — Win32 FFI implementation:
  - Mouse moves use `MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK`
    with `0..65535` coordinates so multi-monitor setups work.
  - Buttons supported: left, right, middle, X1, X2.
  - Wheel and horizontal wheel via `MOUSEEVENTF_WHEEL` /
    `MOUSEEVENTF_HWHEEL`.
  - Keyboard via `SendInput` with virtual-key codes; non-mappable keys
    fall back to `KEYEVENTF_UNICODE`.
  - "Send Ctrl + Alt + Del" works on the desktop session (subject to the
    usual Secure Attention Sequence restrictions; injecting CAD requires
    additional UIAccess privilege which is not in scope here).
- `win_keymap.dart` — translates Flutter `LogicalKeyboardKey` and
  `PhysicalKeyboardKey` constants into Windows VK codes, including
  navigation (arrows, Home/End/PgUp/PgDn), function keys F1–F12,
  modifiers, OEM punctuation, and an `isExtendedKey` helper.

### Host service integration (`lib/services/remote_desktop/remote_desktop_host_service.dart`)

- Each session now owns an `InputInjector` (`createInputInjector()`).
- DataChannel "input" messages are decoded into `RemoteInputEvent` and
  forwarded to the injector unless the session is **view-only** or the
  host disabled control globally in settings.
- The host respects per-session input mode set during the permission
  prompt (`viewOnly` vs `full`).
- Audio loopback fix: hosting now passes the
  `audio: { sampleRate, channels, echoCancellation: false }` constraints
  to `getDisplayMedia` so system audio (when supported by the OS picker)
  is captured cleanly and resampled by libwebrtc.

### Pubspec

Explicit pinning of the FFI dependencies that PR #2 needs at build time:

```yaml
dependencies:
  win32: ^5.10.1
  ffi: ^2.1.3
```

## File changes

**Added**

- `lib/services/remote_desktop/input_injector/input_injector.dart`
- `lib/services/remote_desktop/input_injector/input_injector_stub.dart`
- `lib/services/remote_desktop/input_injector/input_injector_native.dart`
- `lib/services/remote_desktop/input_injector/input_injector_windows.dart`
- `lib/services/remote_desktop/input_injector/win_keymap.dart`

**Modified**

- `lib/pages/remote_desktop_viewer_page.dart` — control toggles,
  pointer/keyboard forwarding, Ctrl+Alt+Del helper.
- `lib/services/remote_desktop/remote_desktop_host_service.dart` —
  injector wiring, DataChannel decoding, audio constraints.
- `pubspec.yaml` — `win32` + `ffi` pinned explicitly.

## Build & analysis

```
flutter pub get           # OK
flutter analyze           # 0 errors (only pre-existing info/avoid_print and naming-style hints from win_keymap)
flutter build windows --debug   # OK (build\windows\x64\runner\Debug\scn.exe)
```

## Limitations / follow-ups

- **macOS / Linux** input injection still no-op. PR #4 will add CGEvent
  / uinput backends.
- **UAC-elevated windows** on the host cannot be controlled by an
  un-elevated SCN process — same restriction as RustDesk and TeamViewer
  unless SCN itself runs elevated.
- **Secure Attention Sequence**: real `Ctrl+Alt+Del` to the secure
  desktop requires `UIAccess=true` and a signed manifest; this PR sends
  the keystroke combination, which is sufficient for in-session use but
  not for the secure desktop login screen.
- **Cursor rendering**: the host still streams the system cursor as part
  of the captured frame; a separate cursor channel (RustDesk-style
  remote cursor sprite) will land in PR #3 alongside file transfer.
- **Latency tuning**: PR #4 will add adaptive bitrate, congestion
  control, and a "low-latency" preset.

## How to test

1. Run two SCN instances on the same LAN (Windows host + any viewer).
2. On the host: open **Settings → Remote Desktop**, enable hosting,
   note password, leave access mode at "Password or prompt".
3. On the viewer: open the **Remote** tab, pick the discovered host (or
   enter IP + password manually) and connect.
4. Approve the prompt on the host. The viewer window opens with the
   remote screen.
5. In the viewer toolbar, flip **Enable input forwarding**. Move the
   mouse, click, type, scroll. The host machine should react in
   real-time.
6. Toggle **Capture keyboard** off to free the local keyboard for app
   shortcuts; toggle on to forward again.
7. Click **Send Ctrl + Alt + Del** — the host should react with the
   shortcut (Task Manager / Run dialog / etc.).

## Next up

- **PR #3** — Total Commander-style dual-pane file manager with
  resumable chunked transfers over the same WebRTC DataChannel, plus
  remote cursor sprite.
- **PR #4** — WAN signalling (rendezvous + STUN/TURN), adaptive
  bitrate / FEC, and macOS / Linux input injection backends.
