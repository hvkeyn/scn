#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "rd_input_service.h"
#include "utils.h"
#include "win7_crash_log.h"
#include "win7_env.h"
#include "win7_iat_patch.h"
#include "win7_prereq.h"

namespace {

void LogExecutableInfo() {
  wchar_t path[MAX_PATH] = {};
  if (GetModuleFileNameW(nullptr, path, MAX_PATH) == 0) {
    return;
  }
  win7_crash_log::Write(path);

  WIN32_FILE_ATTRIBUTE_DATA attrs = {};
  if (!GetFileAttributesExW(path, GetFileExInfoStandard, &attrs)) {
    return;
  }
  ULARGE_INTEGER written = {};
  written.LowPart = attrs.ftLastWriteTime.dwLowDateTime;
  written.HighPart = attrs.ftLastWriteTime.dwHighDateTime;
  SYSTEMTIME utc = {};
  FileTimeToSystemTime(reinterpret_cast<const FILETIME*>(&written),
                       &utc);
  wchar_t stamp[64] = {};
  wsprintfW(stamp, L"scn.exe mtime %04u-%02u-%02u %02u:%02u build %d",
            utc.wYear, utc.wMonth, utc.wDay, utc.wHour, utc.wMinute,
            FLUTTER_VERSION_BUILD);
  win7_crash_log::Write(stamp);
}

void ShowBuildBannerIfWin7() {
  if (!win7_env::IsWindows7()) {
    return;
  }
  wchar_t message[256] = {};
  wsprintfW(message,
            L"SCN Win7 build %d\r\n\r\n"
            L"Если номер сборки не совпадает с загруженным архивом — "
            L"замените scn.exe из zip целиком.",
            FLUTTER_VERSION_BUILD);
  MessageBoxW(nullptr, message, L"SCN", MB_OK | MB_ICONINFORMATION);
}

void LogPlatformUpdateStatus() {
  const HMODULE dxgi = LoadLibraryW(L"dxgi.dll");
  const bool has_dxgi1 =
      dxgi && GetProcAddress(dxgi, "CreateDXGIFactory1") != nullptr;
  if (dxgi) {
    FreeLibrary(dxgi);
  }
  win7_crash_log::Write(has_dxgi1 ? L"platform update ok"
                                  : L"platform update MISSING");
}

void PreloadWin7Shims() {
  static const wchar_t* kShims[] = {
      L"scn_ntdll.dll",
      L"scn_kernel32.dll",
      L"scn_ws2.dll",
      L"scn_dxgi.dll",
      L"scn_d3d11.dll",
  };

  for (const wchar_t* shim : kShims) {
    if (LoadLibraryW(shim)) {
      wchar_t msg[128] = {};
      wsprintfW(msg, L"%s preload ok", shim);
      win7_crash_log::Write(msg);
      continue;
    }
    wchar_t err[128] = {};
    wsprintfW(err, L"%s preload failed err=%lu", shim, GetLastError());
    win7_crash_log::Write(err);
  }
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  win7_env::Apply();
  win7_crash_log::Install();
  win7_crash_log::Write(L"wWinMain start");
  LogExecutableInfo();
  ShowBuildBannerIfWin7();

  // Remote-desktop privileged input helper. When launched with one of the
  // --rd-* switches the process acts as the input service/worker (or
  // installs/removes it) and never starts Flutter.
  win7_crash_log::Write(L"rd_service check");
  {
    int rd_exit_code = 0;
    if (rd_service::HandleCommandLine(&rd_exit_code)) {
      win7_crash_log::Write(L"rd_service handled");
      return rd_exit_code;
    }
  }
  win7_crash_log::Write(L"rd_service skip");

  win7_crash_log::Write(L"prerequisites start");
  if (!win7_prereq::EnsurePrerequisites()) {
    win7_crash_log::Write(L"prerequisites cancelled");
    return EXIT_FAILURE;
  }
  LogPlatformUpdateStatus();
  win7_crash_log::Write(L"prerequisites ok");

  win7_crash_log::Write(L"preload shims");
  PreloadWin7Shims();
  if (!win7_iat::PatchProcessImports()) {
    win7_crash_log::Write(L"IAT patch abort");
    MessageBoxW(nullptr,
                L"Не удалось подготовить Win7-совместимость (IAT patch).\r\n\r\n"
                L"Скопируйте всю папку releases\\windows целиком и проверьте "
                L"наличие scn_ws2.dll рядом с scn.exe.\r\n\r\n"
                L"Лог: %TEMP%\\scn_win7.log",
                L"SCN", MB_OK | MB_ICONERROR);
    return EXIT_FAILURE;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  win7_crash_log::Write(L"CoInitializeEx ok");

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  win7_crash_log::Write(L"FlutterWindow created");
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"SCN", origin, size)) {
    win7_crash_log::Write(L"window.Create failed");
    return EXIT_FAILURE;
  }
  win7_crash_log::Write(L"window.Create ok");
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
