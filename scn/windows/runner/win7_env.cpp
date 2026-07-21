#include "win7_env.h"

#include <stdio.h>
#include <stdlib.h>
#include <windows.h>

namespace win7_env {
namespace {

using RtlGetVersionFn = LONG(WINAPI*)(PRTL_OSVERSIONINFOW);

const RTL_OSVERSIONINFOW& OsVersion() {
  static RTL_OSVERSIONINFOW version = []() {
    RTL_OSVERSIONINFOW info = {};
    info.dwOSVersionInfoSize = sizeof(info);
    if (HMODULE ntdll = GetModuleHandleW(L"ntdll.dll")) {
      if (const auto rtl_get_version = reinterpret_cast<RtlGetVersionFn>(
              GetProcAddress(ntdll, "RtlGetVersion"))) {
        rtl_get_version(&info);
      }
    }
    return info;
  }();
  return version;
}

}  // namespace

bool IsWindows7() {
  const RTL_OSVERSIONINFOW& info = OsVersion();
  return info.dwMajorVersion == 6 && info.dwMinorVersion == 1;
}

void Apply() {
  if (!IsWindows7()) {
    return;
  }

  _wputenv(L"SCN_WIN7=1");
  _wputenv(L"ANGLE_DEFAULT_PLATFORM=D3D9");
  _wputenv(L"ANGLE_PREFER_WARP=1");
  _wputenv(L"FLUTTER_ENGINE_SWITCHES=1");
  _wputenv(L"FLUTTER_ENGINE_SWITCH_1=enable-software-rendering");

  wchar_t temp[MAX_PATH] = {};
  if (GetTempPathW(MAX_PATH, temp) != 0) {
    wchar_t path[MAX_PATH] = {};
    wsprintfW(path, L"%sscn_win7.log", temp);
    FILE* log = nullptr;
    if (_wfopen_s(&log, path, L"a, ccs=UTF-8") == 0 && log) {
      fwprintf(log, L"win7_env: enable-software-rendering\r\n");
      fwprintf(log, L"win7_env: GPU blocked via scn_dxgi/d3d11 shims\r\n");
      fflush(log);
      fclose(log);
    }
  }
}

}  // namespace win7_env
