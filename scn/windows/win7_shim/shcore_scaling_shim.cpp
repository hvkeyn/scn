// Best-effort shim for Windows 7.
//
// flutter_windows.dll (Flutter 3.20+) imports SetProcessDpiAwareness from
// api-ms-win-shcore-scaling-l1-1-1.dll, which does not exist on Windows 7.
// Placing this DLL next to scn.exe satisfies the loader and forwards to
// SetProcessDPIAware when per-monitor APIs are unavailable.

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

extern "C" {

__declspec(dllexport) HRESULT WINAPI SetProcessDpiAwareness(int value) {
  if (value == PROCESS_DPI_UNAWARE) {
    return S_OK;
  }

  using SetProcessDPIAwareFn = BOOL(WINAPI*)();
  HMODULE user32 = GetModuleHandleW(L"user32.dll");
  if (!user32) {
    user32 = LoadLibraryW(L"user32.dll");
  }
  if (!user32) {
    return E_FAIL;
  }

  auto set_process_dpi_aware =
      reinterpret_cast<SetProcessDPIAwareFn>(
          GetProcAddress(user32, "SetProcessDPIAware"));
  if (!set_process_dpi_aware) {
    return E_FAIL;
  }

  return set_process_dpi_aware() ? S_OK : E_FAIL;
}

}  // extern "C"
