// Best-effort shim for Windows 7.
//
// Newer DLLs (libwebrtc, flutter_windows) import DPI helpers from
// api-ms-win-shcore-scaling-l1-1-1.dll, which does not exist on Win7.
// Place this DLL next to scn.exe.

#include <windows.h>

#ifndef PROCESS_DPI_UNAWARE
#define PROCESS_DPI_UNAWARE 0
#endif
#ifndef PROCESS_SYSTEM_DPI_AWARE
#define PROCESS_SYSTEM_DPI_AWARE 1
#endif
#ifndef PROCESS_PER_MONITOR_DPI_AWARE
#define PROCESS_PER_MONITOR_DPI_AWARE 2
#endif

#ifndef MDT_EFFECTIVE_DPI
#define MDT_EFFECTIVE_DPI 0
#endif

#ifndef DEVICE_SCALE_FACTOR_INVALID
#define DEVICE_SCALE_FACTOR_INVALID 0
#endif
#ifndef DEVICE_SCALE_FACTOR_100_PERCENT
#define DEVICE_SCALE_FACTOR_100_PERCENT 100
#endif

namespace {

using SetProcessDPIAwareFn = BOOL(WINAPI*)();

BOOL CallSetProcessDPIAware() {
  HMODULE user32 = GetModuleHandleW(L"user32.dll");
  if (!user32) {
    user32 = LoadLibraryW(L"user32.dll");
  }
  if (!user32) {
    return FALSE;
  }
  auto fn = reinterpret_cast<SetProcessDPIAwareFn>(
      GetProcAddress(user32, "SetProcessDPIAware"));
  return fn ? fn() : FALSE;
}

}  // namespace

extern "C" {

__declspec(dllexport) HRESULT WINAPI SetProcessDpiAwareness(int value) {
  if (value == PROCESS_DPI_UNAWARE) {
    return S_OK;
  }
  return CallSetProcessDPIAware() ? S_OK : E_FAIL;
}

__declspec(dllexport) HRESULT WINAPI GetProcessDpiAwareness(
    HANDLE /*process*/, int* value) {
  if (!value) {
    return E_INVALIDARG;
  }
  *value = PROCESS_SYSTEM_DPI_AWARE;
  return S_OK;
}

__declspec(dllexport) HRESULT WINAPI GetDpiForMonitor(HMONITOR /*hmonitor*/,
                                                      int /*dpiType*/,
                                                      UINT* dpiX,
                                                      UINT* dpiY) {
  if (!dpiX || !dpiY) {
    return E_INVALIDARG;
  }
  // Win7 has no per-monitor DPI API — return standard 96 DPI.
  *dpiX = 96;
  *dpiY = 96;
  return S_OK;
}

__declspec(dllexport) HRESULT WINAPI GetScaleFactorForMonitor(
    HMONITOR /*hmonitor*/,
    int* scale) {
  if (!scale) {
    return E_INVALIDARG;
  }
  *scale = DEVICE_SCALE_FACTOR_100_PERCENT;
  return S_OK;
}

}  // extern "C"
