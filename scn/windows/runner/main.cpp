#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "rd_input_service.h"
#include "utils.h"
#include "win7_crash_log.h"
#include "win7_prereq.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  win7_crash_log::Install();
  win7_crash_log::Write(L"wWinMain start");
  // Remote-desktop privileged input helper. When launched with one of the
  // --rd-* switches the process acts as the input service/worker (or
  // installs/removes it) and never starts Flutter.
  {
    int rd_exit_code = 0;
    if (rd_service::HandleCommandLine(&rd_exit_code)) {
      return rd_exit_code;
    }
  }

  if (!win7_prereq::EnsurePrerequisites()) {
    return EXIT_FAILURE;
  }
  win7_crash_log::Write(L"prerequisites ok");

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
