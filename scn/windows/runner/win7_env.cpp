#include "win7_env.h"

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

  _wputenv(L"ANGLE_DEFAULT_PLATFORM=D3D9");
  _wputenv(L"ANGLE_PREFER_WARP=1");
}

}  // namespace win7_env
