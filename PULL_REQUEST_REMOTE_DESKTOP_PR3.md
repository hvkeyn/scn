# Pull Request: Remote Desktop (PR #3 — Total Commander dual-pane file manager)

## Summary

PR #3 adds a built-in **two-pane file manager** (Total Commander style) on
top of the same RustDesk-like authentication flow that powers the remote
desktop session: from any SCN viewer you can open the host's filesystem,
browse drives / folders, copy files in either direction with progress and
ETA, create / rename / delete entries, and run several transfers in
parallel.

The file manager runs as an **independent capability** alongside the
RemoteDesktop video session — you can open files without ever starting
the WebRTC stream, and the host can choose to expose a read-only view or
restrict the visible roots.

It re-uses the existing HTTP server (no new ports, no extra setup) and
the same password / trusted-peer credentials introduced in PR #1.

## What's new

### Models (`lib/models/remote_file_models.dart`)

- `RemoteFileEntry`, `RemoteFileEntryType` (file / directory / symlink /
  drive / other), `RemoteFileListing` — describe one folder snapshot.
- `FileTransferTask`, `FileTransferDirection` (upload / download),
  `FileTransferState` (queued / preparing / inProgress / completed /
  failed / canceled / paused) — drive the transfers UI with progress,
  speed and error message.
- `RemoteFileSessionParams`, `RemoteFileSessionGrant` — connect-time
  request / response envelopes.

### Host service (`lib/services/remote_desktop/remote_file_host_service.dart`)

A `ChangeNotifier` exposing `shelf` handlers wired into the existing
HTTP server:

- `POST /api/rd/fs/connect` — verify password / trusted peer, mint a
  short-lived `fsToken`, return the device's filesystem roots.
- `GET  /api/rd/fs/list?token=&path=` — directory listing (sorted,
  hidden flag, size, mtime).
- `GET  /api/rd/fs/download?token=&path=` — streamed download with
  HTTP Range support (resume / partial).
- `POST /api/rd/fs/upload?token=&path=` — chunked upload using
  `Content-Range` (1 MiB chunks, append-mode resume).
- `POST /api/rd/fs/mkdir`, `POST /api/rd/fs/delete` (with `recursive`
  flag), `POST /api/rd/fs/rename` — basic mutations.
- `POST /api/rd/fs/disconnect` — explicit teardown.

Security:

- Sessions live in memory and time out after 15 minutes of inactivity
  (`_gc()` runs every minute).
- `fileManagerAllowedRoots` (configurable) limits which paths a viewer
  can see — every operation cross-checks `_isAllowed()`.
- `fileManagerReadOnly` blocks all write endpoints.
- `fileManagerEnabled` (true by default) lets the host turn the whole
  feature off without touching the rest of remote desktop.

### Client (`lib/services/remote_desktop/remote_file_client_service.dart`)

A small async wrapper around the REST API with:

- `connect`, `disconnect`, `list`, `mkdir`, `delete`, `rename`.
- `downloadFile` / `uploadFile` returning a live `FileTransferTask`
  (queued in `transfers`, observable via `ChangeNotifier`).
- Chunked uploads (1 MiB) with `Content-Range`, streamed downloads with
  optional `Range`, and an internal `_SpeedTicker` that produces the
  instantaneous bytes/sec used by the UI.
- Helpers `joinRemote` / `joinLocal` that respect the host's path
  separator (`\` for Windows, `/` for POSIX).

### UI (`lib/pages/remote_file_manager_page.dart`)

A new full-screen page — Total Commander layout:

- Two side-by-side panes (Local / Remote) with multi-selection,
  long-press to drill in, tap to toggle selection, breadcrumb / current
  path bar with up / new-folder buttons.
- Quick-jump chips for remote roots (drives on Windows, `Home` + `/`
  on POSIX).
- Action bar with **Local → Remote**, **Remote → Local**, **Rename**,
  **Delete** (the rename/delete target follows the last-touched pane).
- "Pick local files" launcher that uses the existing
  `file_picker` to pre-select files, jumping to their parent folder.
- Live transfers panel at the bottom: linear progress bar per task,
  state, transferred / total, instantaneous speed, error text on
  failure.
- Read-only awareness: the action buttons surface "Remote is read-only"
  snackbars when the host has locked the file manager.

### Wiring

- `pubspec.yaml` — no new dependencies (uses already-present `http`,
  `uuid`, `file_picker`, `path`).
- `lib/services/http_server_service.dart` — registered the new `/api/rd/fs/*`
  routes and a `RemoteFileHostService` provider parameter.
- `lib/services/app_service.dart` — owns a single `RemoteFileHostService`
  instance, wires it into `setProviders`, applies new
  `RemoteDesktopSettings` from the peer provider, and shuts it down on
  stop / dispose.
- `lib/main.dart` — registers `RemoteFileHostService` in the provider
  tree so widgets can `context.watch` if needed.
- `lib/models/remote_desktop_models.dart` — three new fields on
  `RemoteDesktopSettings`: `fileManagerEnabled`, `fileManagerReadOnly`,
  `fileManagerAllowedRoots` (default `[]`).
- `lib/providers/remote_peer_provider.dart` — three new setters
  (`setRemoteDesktopFileManagerEnabled`,
  `setRemoteDesktopFileManagerReadOnly`,
  `setRemoteDesktopFileManagerAllowedRoots`).
- `lib/pages/tabs/settings_tab.dart` — Remote Desktop card now exposes
  *Allow remote file manager* and *File manager — read only* switches.
- `lib/pages/remote_desktop_page.dart` — *Open files* button on the
  manual-connect card and a folder icon on every discovered LAN peer
  open the file manager directly.

## Build & analysis

```
flutter pub get          # OK
flutter analyze          # 0 errors (only info/avoid_print and naming-style hints from PR #1/#2)
flutter build windows --debug
                         # OK (build\windows\x64\runner\Debug\scn.exe)
```

## How to test

1. On the host, open **Settings → Remote Desktop**, enable hosting (so
   a password is generated), keep **Allow remote file manager** on, and
   optionally toggle **File manager — read only** if you only want to
   ship files in one direction.
2. On any SCN viewer (same LAN or via the WAN signalling that lands in
   PR #4) open the **Remote** tab.
3. Either pick the host from "Discovered on LAN" and tap the folder
   icon, or fill in IP + port + password manually and click **Open
   files**.
4. The file manager opens with the local home / `USERPROFILE` on the
   left and the host's drives / `Home` on the right. Click a drive chip
   on the right to drill in. Tap rows to multi-select.
5. **Local → Remote** and **Remote → Local** start chunked transfers and
   show a live progress bar with bytes/sec at the bottom of the screen.
6. **Rename** / **Delete** affect the last-touched pane; remote
   mutations are blocked when read-only.
7. Close the page (back arrow) to disconnect — the `fsToken` is
   invalidated immediately (and the host garbage-collects idle sessions
   after 15 minutes anyway).

## Limitations / follow-ups (will land in PR #4)

- **Recursive directory copy** is not yet implemented (UI surfaces a
  snackbar). The protocol already supports it; we'll add a
  walker on the next PR.
- **Drag & drop**, clipboard cut/paste/keyboard shortcuts (`F5` copy,
  `F6` move, `F7` mkdir, `F8` delete, `Tab` switch pane) are deferred.
- **HTTPS / self-signed cert** is the same as the rest of SCN — the
  WAN-aware variant in PR #4 will introduce TLS pinning.
- **Resume after process restart** — the current resume logic survives
  a flaky network (the chunk loop continues), but a hard restart of the
  viewer requires re-uploading from offset 0. Persistent transfer
  state will follow.

## Next up

- **PR #4** — WAN signalling (rendezvous / STUN / TURN), adaptive
  bitrate / FEC, recursive directory copy + drag-and-drop, and macOS /
  Linux input injection backends.
