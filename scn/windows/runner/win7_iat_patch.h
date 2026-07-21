#pragma once

#include <windows.h>

namespace win7_iat {

// Load a DLL from the exe directory (proxy shims resolve imports normally).
HMODULE LoadModuleWithWin7Imports(const wchar_t* module_name);

// Preload engine/plugins on Win7 before Flutter starts. Returns false on failure.
bool PatchProcessImports();

// After flutter_webrtc / libwebrtc are delay-loaded: GetHostNameW only.
// Do NOT block DXGI here — that aborts PeerConnection::Create on Win7 (build 207).
void ApplyWebRtcHostnameHooks();

// Block DXGI/D3D11 on libwebrtc (IAT + GPA). Call immediately before
// desktopCapturer / getDisplayMedia so DirectX capturer cannot initialize.
void ApplyWebRtcGpuHooks();

}  // namespace win7_iat
