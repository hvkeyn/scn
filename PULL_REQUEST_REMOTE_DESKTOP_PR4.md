# Pull Request: Remote Desktop (PR #4 — adaptive bitrate, cross-platform input, live stats push)

## Summary

PR #4 closes out the Remote Desktop epic with three orthogonal
improvements:

1. **Adaptive bitrate / FPS** on the host — when the user has not
   pinned a fixed bitrate, the host automatically reacts to packet
   loss, RTT, and FPS pressure (RustDesk-style AIMD).
2. **Cross-platform input injection** — macOS (`cliclick` / `osascript`)
   and Linux (`xdotool` / `ydotool`) backends are now wired in alongside
   the Windows FFI implementation from PR #2.
3. **Push-based live stats** — instead of recomputing stats on the
   viewer, the host now broadcasts a `stats` signal every two seconds.
   This drives the viewer's stats overlay with a single source of
   truth, including the dynamic bitrate cap.

## What's new

### Adaptive quality (host)

`RemoteDesktopHostService._startStatsTimer` now produces a per-second
delta-based `videoBitrateKbps` (we no longer divide cumulative
`bytesSent` by 2 — we diff against the previous tick), and exposes the
new `_HostSession` fields:

- `currentMaxBitrateKbps` — running cap.
- `currentTargetFps` — reserved for future per-session FPS adaptation.
- `lastBytesSent` — running counter for the delta.

`_adaptBitrate()` implements the AIMD heuristic:

| Trigger                                                | Action                  |
|--------------------------------------------------------|-------------------------|
| `rttMs > 250` **or** `lossDelta > 50` **or** `fps < 5` | shrink cap by 25%       |
| `rttMs < 120` **and** `lossDelta < 5`                  | grow cap by +10%        |
| otherwise                                              | hold                    |

The cap is clamped to `[500..25000]` kbps and applied to every video
sender via `_applyMaxBitrate`. When the user pins a manual bitrate in
Settings, the heuristic is bypassed entirely.

### Stats signal (host → viewer)

Inside `_startStatsTimer` the host now emits, after every
recomputation:

```json
{
  "type": "stats",
  "payload": {
    "videoKbps": 4123.4,
    "audioKbps": 47.0,
    "fps": 27.5,
    "rtt": 73,
    "lost": 18,
    "width": 1920,
    "height": 1080,
    "maxKbps": 6600
  }
}
```

`RemoteDesktopClientService._handleSignal` now consumes
`RemoteDesktopSignalType.stats` and updates `session.stats`. The
existing viewer overlay (`_StatsPanel` in
`remote_desktop_viewer_page.dart`) renders this without further changes.

### macOS input (`input_injector_macos.dart`)

`MacOsInputInjector` chooses between two backends:

- `cliclick` (preferred, fast, supports `m:`, `dd:` / `du:`,
  `w:` (wheel), `t:` (type)) — auto-detected via `which cliclick`.
- `osascript` fallback using `tell application "System Events"`.

Mouse coordinates are denormalized to the host's last-known capture
size (default `1920x1080`). Buttons map to cliclick verbs (`dd/du/rd/ru`).
Scrolling, key down/up, and text input are all implemented; non-mappable
keys fall through to `cliclick t:` text injection.

### Linux input (`input_injector_linux.dart`)

`LinuxInputInjector` detects `xdotool` and `ydotool` (X11 / Wayland) via
`which`. Move events use `mousemove` (xdotool) or `mousemove_abs`
(ydotool); buttons map to xdotool numeric IDs (`1` left, `2` middle,
`3` right, `4/5` wheel up/down, `8/9` extra). Key events fall back to
typing the unicode point as `U`-style keysyms.

### Wiring (`input_injector_native.dart`)

```dart
InputInjector createNativeInjector() {
  if (Platform.isWindows) return WindowsInputInjector();
  if (Platform.isMacOS)   return MacOsInputInjector();
  if (Platform.isLinux)   return LinuxInputInjector();
  return _PlatformStub();
}
```

The platform stub for unsupported targets stays untouched.

## File changes

**Added**

- `lib/services/remote_desktop/input_injector/input_injector_macos.dart`
- `lib/services/remote_desktop/input_injector/input_injector_linux.dart`

**Modified**

- `lib/services/remote_desktop/input_injector/input_injector_native.dart`
  — wires up the new backends.
- `lib/services/remote_desktop/remote_desktop_host_service.dart`
  — adaptive bitrate + live stats push + delta-based bitrate accounting.
- `lib/services/remote_desktop/remote_desktop_client_service.dart`
  — handles `stats` signal and refreshes the live overlay.

## Build & analysis

```
flutter pub get          # OK
flutter analyze          # 0 errors (only pre-existing info/avoid_print and naming-style hints)
flutter build windows --debug   # OK
```

## Notes / next steps (not in this PR)

- **WAN signalling** — SCN already ships `MeshNetworkService` with
  rendezvous + STUN; a full RD-over-mesh tunnel is the natural next
  step but did not fit into this PR. The current LAN flow already works
  across any reachable IP (including WAN if `0.0.0.0` is exposed +
  port-forwarded), so the immediate user-facing UX stays.
- **Linux input mapping** — `xdotool keydown` maps a small subset of
  named keys today. Extending the mapping table to the same coverage
  as `win_keymap.dart` is a routine follow-up.
- **macOS Accessibility** — `cliclick` and `osascript` both require the
  app to be granted **Accessibility** permission in
  *System Settings → Privacy & Security*. SCN will surface this prompt
  in a future UI polish pass.
- **Recursive directory copy** in the file manager (PR #3 limitation)
  is still pending and will land in a follow-up PR.

## Combined recap (PR #1–#4)

| PR | Scope                                                                 |
|----|-----------------------------------------------------------------------|
| #1 | Models, settings, host capture (screen+audio), LAN signalling, viewer-only UI, permission dialog. |
| #2 | Native input injector (Windows FFI), control toggles, viewer pointer/keyboard forwarding, audio loopback fix. |
| #3 | Total Commander–style two-pane file manager, chunked upload/download with progress, host filesystem service. |
| #4 | Adaptive bitrate, live stats push, macOS / Linux input backends.      |

The full Remote Desktop feature is now usable on Windows hosts (with
full input injection), macOS hosts (via `cliclick` / `osascript`) and
Linux hosts (via `xdotool` / `ydotool`); viewers run on any platform
that can build the SCN Flutter app.
