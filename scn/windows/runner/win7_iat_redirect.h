#pragma once

#include <windows.h>

namespace win7_iat_redirect {

// GetHostNameW → scn_ws2 (avoids Win7 hangs on STUN/TURN hostnames).
bool PatchModuleHostnameImports(HMODULE module);

// DXGI/D3D11 → block shims (force GDI capturer). Call only before capture —
// applying this before PeerConnection::Create can abort libwebrtc on Win7.
bool PatchModuleGpuImports(HMODULE module);

}  // namespace win7_iat_redirect
