#include "win7_crash_log.h"

#include <windows.h>

#include <stdio.h>

namespace win7_crash_log {
namespace {

bool IsWindows7() {
  OSVERSIONINFOEXW info = {};
  info.dwOSVersionInfoSize = sizeof(info);
  info.dwMajorVersion = 6;
  info.dwMinorVersion = 1;
  DWORDLONG mask = 0;
  VER_SET_CONDITION(mask, VER_MAJORVERSION, VER_EQUAL);
  VER_SET_CONDITION(mask, VER_MINORVERSION, VER_EQUAL);
  return VerifyVersionInfoW(&info, VER_MAJORVERSION | VER_MINORVERSION, mask) != FALSE;
}

FILE* LogFile() {
  static FILE* file = nullptr;
  if (file) {
    return file;
  }
  wchar_t temp[MAX_PATH] = {};
  if (GetTempPathW(MAX_PATH, temp) == 0) {
    return nullptr;
  }
  wchar_t path[MAX_PATH] = {};
  wsprintfW(path, L"%sscn_win7.log", temp);
  _wfopen_s(&file, path, L"a");
  return file;
}

LONG WINAPI UnhandledExceptionFilter(_EXCEPTION_POINTERS* info) {
  if (FILE* log = LogFile()) {
    const DWORD code =
        info && info->ExceptionRecord ? info->ExceptionRecord->ExceptionCode : 0;
    void* const address =
        info && info->ExceptionRecord ? info->ExceptionRecord->ExceptionAddress
                                      : nullptr;
    fwprintf(log, L"Unhandled exception code=0x%08lX at %p\r\n", code, address);
    if (address) {
      HMODULE module = nullptr;
      wchar_t module_path[MAX_PATH] = {};
      if (GetModuleHandleExW(
              GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                  GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
              static_cast<LPCWSTR>(address), &module) &&
          module &&
          GetModuleFileNameW(module, module_path, MAX_PATH) != 0) {
        const DWORD_PTR base = reinterpret_cast<DWORD_PTR>(module);
        const DWORD_PTR offset =
            reinterpret_cast<DWORD_PTR>(address) - base;
        fwprintf(log, L"  in %s+0x%llX\r\n", module_path,
                 static_cast<unsigned long long>(offset));
      }
    }
    fflush(log);
  }
  return EXCEPTION_CONTINUE_SEARCH;
}

}  // namespace

void Install() {
  if (!IsWindows7()) {
    return;
  }
  SetUnhandledExceptionFilter(UnhandledExceptionFilter);
  if (FILE* log = LogFile()) {
    fwprintf(log, L"--- SCN start build %d ---\r\n", FLUTTER_VERSION_BUILD);
    fflush(log);
  }
}

void Write(const wchar_t* message) {
  if (!IsWindows7() || !message) {
    return;
  }
  if (FILE* log = LogFile()) {
    fwprintf(log, L"%s\r\n", message);
    fflush(log);
  }
}

}  // namespace win7_crash_log
