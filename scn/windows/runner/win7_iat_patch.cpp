#include "win7_iat_patch.h"

#include "win7_crash_log.h"
#include "win7_env.h"
#include "win7_iat_redirect.h"

#include <windows.h>

namespace win7_iat {
namespace {

// LoadLibraryEx flag: resolve the DLL's own imports normally, but search the
// EXE directory first.  We do NOT use DONT_RESOLVE_DLL_REFERENCES here: the
// shims (scn_ntdll/scn_kernel32/scn_ws2) are full proxies generated from
// flutter_windows.dll's imports, so the Windows loader can resolve every
// import on its own — including the Win8+ symbols that the proxies replace
// with local Scn* implementations.
constexpr DWORD kLoadWithAlteredSearchPath = 0x00000008;

bool GetExeDirectory(wchar_t* out, size_t out_chars) {
  if (GetModuleFileNameW(nullptr, out, static_cast<DWORD>(out_chars)) == 0) {
    return false;
  }
  wchar_t* slash = wcsrchr(out, L'\\');
  if (!slash) {
    return false;
  }
  slash[1] = L'\0';
  return true;
}

bool BuildModulePath(const wchar_t* module_name, wchar_t* out, size_t out_chars) {
  wchar_t dir[MAX_PATH] = {};
  if (!GetExeDirectory(dir, MAX_PATH)) {
    return false;
  }
  if (wcslen(dir) + wcslen(module_name) + 1 >= out_chars) {
    return false;
  }
  wcscpy_s(out, out_chars, dir);
  wcscat_s(out, out_chars, module_name);
  return true;
}

void LogModuleStep(const wchar_t* message, const wchar_t* module_name) {
  wchar_t msg[256] = {};
  wsprintfW(msg, L"%s %s", message, module_name);
  win7_crash_log::Write(msg);
}

// Hook GetProcAddress in a freshly loaded module so that ANGLE's runtime
// D3D11/DXGI lookups are redirected to our GPU-block shims on Win7.
void ApplyFlutterGpuHooks(HMODULE module, const wchar_t* module_name) {
  if (!module) {
    return;
  }

  wchar_t step[128] = {};
  wsprintfW(step, L"gpu hooks %s", module_name);
  win7_crash_log::Write(step);

  // Hostname first (STUN), then DXGI/D3D11 block for software rendering.
  win7_iat_redirect::PatchModuleHostnameImports(module);
  win7_iat_redirect::PatchModuleGpuImports(module);

  // Hook GetProcAddress so dynamic D3D11/DXGI resolution by ANGLE also goes
  // through the shims, and RtlAddGrowableFunctionTable/etc. via GPA resolve
  // to scn_ntdll.
  using PatchFlutterGpaFn = BOOL(WINAPI*)(HMODULE);
  const HMODULE scn_ntdll = GetModuleHandleW(L"scn_ntdll.dll");
  const PatchFlutterGpaFn patch =
      scn_ntdll ? reinterpret_cast<PatchFlutterGpaFn>(
                      GetProcAddress(scn_ntdll, "ScnPatchFlutterGetProcAddress"))
                : nullptr;
  if (!patch || !patch(module)) {
    win7_crash_log::Write(L"gpa post-load patch failed");
  } else {
    win7_crash_log::Write(L"gpa post-load patch ok");
  }
}

void ApplyWebRtcHostnameOnly(HMODULE module, const wchar_t* module_name) {
  if (!module) {
    return;
  }
  wchar_t step[128] = {};
  wsprintfW(step, L"hostname hooks %s", module_name);
  win7_crash_log::Write(step);
  win7_iat_redirect::PatchModuleHostnameImports(module);
}

}  // namespace

HMODULE LoadModuleWithWin7Imports(const wchar_t* module_name) {
  HMODULE existing = GetModuleHandleW(module_name);
  if (existing) {
    return existing;
  }

  wchar_t path[MAX_PATH] = {};
  if (!BuildModulePath(module_name, path, MAX_PATH)) {
    win7_crash_log::Write(L"module path failed");
    return nullptr;
  }

  LogModuleStep(L"LoadLibrary", path);
  // Normal load: the proxy shims re-export every needed symbol, so the loader
  // resolves imports the standard way.  This avoids the crashes that
  // DONT_RESOLVE_DLL_REFERENCES + manual IAT fixups caused on Win7.
  HMODULE module = LoadLibraryExW(path, nullptr, kLoadWithAlteredSearchPath);
  if (!module) {
    module = LoadLibraryW(path);
  }
  if (!module) {
    wchar_t msg[256] = {};
    wsprintfW(msg, L"load failed %s err=%lu", path, GetLastError());
    win7_crash_log::Write(msg);
    return nullptr;
  }

  LogModuleStep(L"loaded", module_name);
  return module;
}

bool PatchProcessImports() {
  if (!win7_env::IsWindows7()) {
    return true;
  }

  win7_crash_log::Write(L"Win7 module preload begin");

  // Preload the engine and every plugin that statically imports Win8+ symbols.
  // Loading them here (instead of lazily) lets us apply GPU hooks to
  // flutter_windows.dll before the engine spins up the renderer.
  // Win7: skip libwebrtc/tray plugins — they crash after the first frame.
  // Win7: only preload the Flutter engine DLL (plugins register later on Win10+).
  static const wchar_t* kModules[] = {
      L"flutter_windows.dll",
  };

  static const wchar_t* kGpuHookModules[] = {
      L"flutter_windows.dll",
  };

  for (const wchar_t* module_name : kModules) {
    wchar_t step[128] = {};
    wsprintfW(step, L"preload %s", module_name);
    win7_crash_log::Write(step);
    if (!LoadModuleWithWin7Imports(module_name)) {
      win7_crash_log::Write(L"Win7 module preload failed");
      return false;
    }

    const HMODULE loaded = GetModuleHandleW(module_name);
    for (const wchar_t* hook_name : kGpuHookModules) {
      if (loaded && _wcsicmp(module_name, hook_name) == 0) {
        ApplyFlutterGpuHooks(loaded, module_name);
        break;
      }
    }
  }

  win7_crash_log::Write(L"Win7 module preload done");
  return true;
}

void ApplyWebRtcHostnameHooks() {
  if (!win7_env::IsWindows7()) {
    return;
  }

  static bool libwebrtc_done = false;
  static bool plugin_done = false;

  if (!libwebrtc_done) {
    if (const HMODULE libwebrtc = GetModuleHandleW(L"libwebrtc.dll")) {
      ApplyWebRtcHostnameOnly(libwebrtc, L"libwebrtc.dll");
      libwebrtc_done = true;
    }
  }
  if (!plugin_done) {
    if (const HMODULE plugin = GetModuleHandleW(L"flutter_webrtc_plugin.dll")) {
      ApplyWebRtcHostnameOnly(plugin, L"flutter_webrtc_plugin.dll");
      plugin_done = true;
    }
  }
}

void ApplyWebRtcGpuHooks() {
  if (!win7_env::IsWindows7()) {
    return;
  }

  static bool libwebrtc_done = false;
  static bool plugin_done = false;

  // Hostname first (idempotent), then full DXGI/D3D11 + GPA block.
  ApplyWebRtcHostnameHooks();

  if (!libwebrtc_done) {
    if (const HMODULE libwebrtc = GetModuleHandleW(L"libwebrtc.dll")) {
      win7_crash_log::Write(L"gpu hooks libwebrtc.dll (deferred until capture)");
      ApplyFlutterGpuHooks(libwebrtc, L"libwebrtc.dll");
      libwebrtc_done = true;
    }
  }
  if (!plugin_done) {
    if (const HMODULE plugin = GetModuleHandleW(L"flutter_webrtc_plugin.dll")) {
      win7_crash_log::Write(
          L"gpu hooks flutter_webrtc_plugin.dll (deferred until capture)");
      ApplyFlutterGpuHooks(plugin, L"flutter_webrtc_plugin.dll");
      plugin_done = true;
    }
  }
}

}  // namespace win7_iat
