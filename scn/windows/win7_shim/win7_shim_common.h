#pragma once

#include <stdio.h>
#include <windows.h>

namespace scn_win7 {

inline bool IsWindows7() {
  static bool win7 = []() {
    OSVERSIONINFOEXW info = {};
    info.dwOSVersionInfoSize = sizeof(info);
    using RtlGetVersionFn = LONG(WINAPI*)(PRTL_OSVERSIONINFOW);
    const auto rtl_get_version = reinterpret_cast<RtlGetVersionFn>(
        GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "RtlGetVersion"));
    if (!rtl_get_version ||
        rtl_get_version(reinterpret_cast<PRTL_OSVERSIONINFOW>(&info)) != 0) {
      return false;
    }
    return info.dwMajorVersion == 6 && info.dwMinorVersion == 1;
  }();
  return win7;
}

inline void LogShim(const wchar_t* message) {
  wchar_t temp[MAX_PATH] = {};
  if (GetTempPathW(MAX_PATH, temp) == 0) {
    return;
  }
  wchar_t path[MAX_PATH] = {};
  wsprintfW(path, L"%sscn_win7.log", temp);
  FILE* log = nullptr;
  if (_wfopen_s(&log, path, L"a, ccs=UTF-8") != 0 || !log) {
    return;
  }
  fwprintf(log, L"%s\r\n", message);
  fflush(log);
  fclose(log);
}

inline HMODULE LoadSystemModule(const wchar_t* file_name) {
  wchar_t system_dir[MAX_PATH] = {};
  if (GetSystemDirectoryW(system_dir, MAX_PATH) == 0) {
    return nullptr;
  }
  wchar_t path[MAX_PATH] = {};
  if (wsprintfW(path, L"%s\\%s", system_dir, file_name) <= 0) {
    return nullptr;
  }
  return LoadLibraryW(path);
}

inline bool ModuleBaseNameMatches(HMODULE mod, const wchar_t* name) {
  if (!mod || !name) {
    return false;
  }
  wchar_t path[MAX_PATH] = {};
  if (GetModuleFileNameW(mod, path, MAX_PATH) == 0) {
    return false;
  }
  const wchar_t* base = wcsrchr(path, L'\\');
  base = base ? base + 1 : path;
  return _wcsicmp(base, name) == 0;
}

// Always block GPU on Win7 (Flutter software rendering + WebRTC GDI capture).
// Desktop Duplication (IDXGIOutputDuplication) is Win8+; allowing DXGI for
// libwebrtc on Win7 lets ScreenCapturerWinDirectx initialize and abort the
// process. Blocking forces the GDI BitBlt capturer path instead.
inline bool ShouldBlockGpuOnWin7() { return IsWindows7(); }

}  // namespace scn_win7
