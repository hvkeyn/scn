#include "rd_input_service.h"

#include <windows.h>
#include <sddl.h>
#include <userenv.h>

#include <string>

namespace rd_service {

namespace {

constexpr wchar_t kServiceName[] = L"ScnRemoteInput";
constexpr wchar_t kServiceDisplay[] = L"SCN Remote Input";
constexpr wchar_t kPipeName[] = L"\\\\.\\pipe\\scn_rd_input";

// Wire protocol shared with Dart (service_input_bridge.dart). Keep in sync!
#pragma pack(push, 1)
struct RdInputCommand {
  int32_t type;        // 1 = mouse, 2 = keyboard
  int32_t mouseFlags;  // MOUSEEVENTF_*
  int32_t mouseData;   // wheel delta / XBUTTON
  int32_t dx;          // absolute X (0..65535) for mouse move
  int32_t dy;          // absolute Y (0..65535) for mouse move
  int32_t wVk;         // virtual key (keyboard)
  int32_t wScan;       // scan code / unicode char (keyboard)
  int32_t keyFlags;    // KEYEVENTF_*
};
#pragma pack(pop)

constexpr int32_t kCmdMouse = 1;
constexpr int32_t kCmdKeyboard = 2;

// ---------------------------------------------------------------------------
// Worker: runs as SYSTEM in the user session, replays input.
// ---------------------------------------------------------------------------

HDESK g_attached_desktop = nullptr;
wchar_t g_current_desktop_name[256] = L"";

// Attaches this thread to the desktop currently receiving input. During UAC the
// input desktop switches to "Winlogon" (secure desktop); the rest of the time it
// is "Default". Switching is required so SendInput targets the visible desktop.
void EnsureInputDesktop() {
  HDESK desk = OpenInputDesktop(0, FALSE, GENERIC_ALL);
  if (!desk) {
    return;
  }
  wchar_t name[256] = L"";
  DWORD needed = 0;
  if (GetUserObjectInformationW(desk, UOI_NAME, name, sizeof(name), &needed) &&
      wcscmp(name, g_current_desktop_name) == 0) {
    // Already attached to this desktop.
    CloseDesktop(desk);
    return;
  }
  if (SetThreadDesktop(desk)) {
    wcscpy_s(g_current_desktop_name, name);
    if (g_attached_desktop) {
      CloseDesktop(g_attached_desktop);
    }
    g_attached_desktop = desk;
  } else {
    CloseDesktop(desk);
  }
}

void InjectCommand(const RdInputCommand& cmd) {
  INPUT input = {};
  if (cmd.type == kCmdMouse) {
    input.type = INPUT_MOUSE;
    input.mi.dwFlags = static_cast<DWORD>(cmd.mouseFlags);
    input.mi.mouseData = static_cast<DWORD>(cmd.mouseData);
    input.mi.dx = cmd.dx;
    input.mi.dy = cmd.dy;
  } else if (cmd.type == kCmdKeyboard) {
    input.type = INPUT_KEYBOARD;
    input.ki.wVk = static_cast<WORD>(cmd.wVk);
    input.ki.wScan = static_cast<WORD>(cmd.wScan);
    input.ki.dwFlags = static_cast<DWORD>(cmd.keyFlags);
  } else {
    return;
  }
  SendInput(1, &input, sizeof(INPUT));
}

// Builds a security descriptor that lets a (High-integrity) interactive process
// connect to the SYSTEM-owned pipe: grant Authenticated Users + SYSTEM, and set
// a Low mandatory label so write-up across integrity levels is permitted.
bool BuildPipeSecurity(SECURITY_ATTRIBUTES* sa) {
  const wchar_t* sddl =
      L"D:(A;;GRGW;;;AU)(A;;GA;;;BA)(A;;GA;;;SY)S:(ML;;NW;;;LW)";
  PSECURITY_DESCRIPTOR sd = nullptr;
  if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(
          sddl, SDDL_REVISION_1, &sd, nullptr)) {
    return false;
  }
  sa->nLength = sizeof(SECURITY_ATTRIBUTES);
  sa->lpSecurityDescriptor = sd;
  sa->bInheritHandle = FALSE;
  return true;
}

int RunWorker() {
  SECURITY_ATTRIBUTES sa = {};
  const bool have_sa = BuildPipeSecurity(&sa);

  for (;;) {
    HANDLE pipe = CreateNamedPipeW(
        kPipeName, PIPE_ACCESS_INBOUND,
        PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT,
        1, 0, sizeof(RdInputCommand) * 64, 0, have_sa ? &sa : nullptr);
    if (pipe == INVALID_HANDLE_VALUE) {
      Sleep(1000);
      continue;
    }

    BOOL connected = ConnectNamedPipe(pipe, nullptr)
                         ? TRUE
                         : (GetLastError() == ERROR_PIPE_CONNECTED);
    if (!connected) {
      CloseHandle(pipe);
      continue;
    }

    RdInputCommand cmd = {};
    DWORD read = 0;
    while (ReadFile(pipe, &cmd, sizeof(cmd), &read, nullptr) &&
           read == sizeof(cmd)) {
      EnsureInputDesktop();
      InjectCommand(cmd);
    }

    DisconnectNamedPipe(pipe);
    CloseHandle(pipe);
  }
}

// ---------------------------------------------------------------------------
// Service: runs as LocalSystem in session 0, keeps a worker alive in the
// active console session.
// ---------------------------------------------------------------------------

SERVICE_STATUS_HANDLE g_status_handle = nullptr;
SERVICE_STATUS g_status = {};
HANDLE g_stop_event = nullptr;
PROCESS_INFORMATION g_worker = {};

void KillWorker() {
  if (g_worker.hProcess) {
    TerminateProcess(g_worker.hProcess, 0);
    CloseHandle(g_worker.hProcess);
  }
  if (g_worker.hThread) {
    CloseHandle(g_worker.hThread);
  }
  g_worker = {};
}

bool WorkerAlive() {
  if (!g_worker.hProcess) {
    return false;
  }
  return WaitForSingleObject(g_worker.hProcess, 0) == WAIT_TIMEOUT;
}

// Launches scn.exe --rd-worker as SYSTEM inside the active console session.
bool LaunchWorker() {
  KillWorker();

  DWORD session_id = WTSGetActiveConsoleSessionId();
  if (session_id == 0xFFFFFFFF) {
    return false;  // No active console session (e.g. nobody logged in yet).
  }

  HANDLE proc_token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(),
                        TOKEN_DUPLICATE | TOKEN_QUERY | TOKEN_ASSIGN_PRIMARY |
                            TOKEN_ADJUST_DEFAULT | TOKEN_ADJUST_SESSIONID,
                        &proc_token)) {
    return false;
  }

  HANDLE dup_token = nullptr;
  bool ok = DuplicateTokenEx(proc_token, MAXIMUM_ALLOWED, nullptr,
                             SecurityIdentification, TokenPrimary, &dup_token);
  CloseHandle(proc_token);
  if (!ok) {
    return false;
  }

  SetTokenInformation(dup_token, TokenSessionId, &session_id,
                      sizeof(session_id));

  wchar_t exe_path[MAX_PATH] = {};
  GetModuleFileNameW(nullptr, exe_path, MAX_PATH);
  std::wstring cmd = L"\"" + std::wstring(exe_path) + L"\" --rd-worker";

  STARTUPINFOW si = {};
  si.cb = sizeof(si);
  si.lpDesktop = const_cast<LPWSTR>(L"winsta0\\default");

  LPVOID env = nullptr;
  CreateEnvironmentBlock(&env, dup_token, FALSE);

  PROCESS_INFORMATION pi = {};
  std::wstring mutable_cmd = cmd;
  ok = CreateProcessAsUserW(
      dup_token, nullptr, &mutable_cmd[0], nullptr, nullptr, FALSE,
      CREATE_UNICODE_ENVIRONMENT | CREATE_NO_WINDOW, env,
      nullptr, &si, &pi);

  if (env) {
    DestroyEnvironmentBlock(env);
  }
  CloseHandle(dup_token);

  if (!ok) {
    return false;
  }
  g_worker = pi;
  return true;
}

void ReportStatus(DWORD state) {
  g_status.dwCurrentState = state;
  SetServiceStatus(g_status_handle, &g_status);
}

DWORD WINAPI ServiceHandlerEx(DWORD control, DWORD event_type,
                              LPVOID /*event_data*/, LPVOID /*context*/) {
  switch (control) {
    case SERVICE_CONTROL_STOP:
    case SERVICE_CONTROL_SHUTDOWN:
      ReportStatus(SERVICE_STOP_PENDING);
      if (g_stop_event) {
        SetEvent(g_stop_event);
      }
      return NO_ERROR;
    case SERVICE_CONTROL_SESSIONCHANGE:
      // Re-target worker when the interactive session changes (logon, unlock,
      // fast user switch, RDP connect).
      if (event_type == WTS_CONSOLE_CONNECT ||
          event_type == WTS_SESSION_LOGON ||
          event_type == WTS_SESSION_UNLOCK) {
        LaunchWorker();
      }
      return NO_ERROR;
    case SERVICE_CONTROL_INTERROGATE:
      return NO_ERROR;
    default:
      return ERROR_CALL_NOT_IMPLEMENTED;
  }
}

void WINAPI ServiceMain(DWORD /*argc*/, LPWSTR* /*argv*/) {
  g_status_handle =
      RegisterServiceCtrlHandlerExW(kServiceName, ServiceHandlerEx, nullptr);
  if (!g_status_handle) {
    return;
  }

  g_status.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
  g_status.dwControlsAccepted = SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN |
                                SERVICE_ACCEPT_SESSIONCHANGE;
  g_status.dwWin32ExitCode = NO_ERROR;
  g_status.dwServiceSpecificExitCode = 0;
  g_status.dwCheckPoint = 0;
  g_status.dwWaitHint = 0;

  ReportStatus(SERVICE_START_PENDING);
  g_stop_event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  ReportStatus(SERVICE_RUNNING);

  LaunchWorker();

  for (;;) {
    DWORD wait = WaitForSingleObject(g_stop_event, 3000);
    if (wait == WAIT_OBJECT_0) {
      break;
    }
    if (!WorkerAlive()) {
      LaunchWorker();
    }
  }

  KillWorker();
  ReportStatus(SERVICE_STOPPED);
}

int RunServiceDispatcher() {
  SERVICE_TABLE_ENTRYW table[] = {
      {const_cast<LPWSTR>(kServiceName), ServiceMain},
      {nullptr, nullptr},
  };
  if (!StartServiceCtrlDispatcherW(table)) {
    return 1;
  }
  return 0;
}

// ---------------------------------------------------------------------------
// Install / uninstall (run from the elevated main app).
// ---------------------------------------------------------------------------

int InstallService() {
  wchar_t exe_path[MAX_PATH] = {};
  GetModuleFileNameW(nullptr, exe_path, MAX_PATH);
  std::wstring bin = L"\"" + std::wstring(exe_path) + L"\" --rd-service";

  SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_ALL_ACCESS);
  if (!scm) {
    return 1;
  }

  SC_HANDLE svc = OpenServiceW(scm, kServiceName, SERVICE_ALL_ACCESS);
  if (!svc) {
    svc = CreateServiceW(scm, kServiceName, kServiceDisplay, SERVICE_ALL_ACCESS,
                         SERVICE_WIN32_OWN_PROCESS, SERVICE_DEMAND_START,
                         SERVICE_ERROR_NORMAL, bin.c_str(), nullptr, nullptr,
                         nullptr, nullptr, nullptr);
  } else {
    ChangeServiceConfigW(svc, SERVICE_WIN32_OWN_PROCESS, SERVICE_DEMAND_START,
                         SERVICE_ERROR_NORMAL, bin.c_str(), nullptr, nullptr,
                         nullptr, nullptr, nullptr, kServiceDisplay);
  }

  int result = 1;
  if (svc) {
    SERVICE_STATUS_PROCESS ssp = {};
    DWORD bytes = 0;
    QueryServiceStatusEx(svc, SC_STATUS_PROCESS_INFO,
                         reinterpret_cast<LPBYTE>(&ssp), sizeof(ssp), &bytes);
    if (ssp.dwCurrentState != SERVICE_RUNNING &&
        ssp.dwCurrentState != SERVICE_START_PENDING) {
      StartServiceW(svc, 0, nullptr);
    }
    result = 0;
    CloseServiceHandle(svc);
  }
  CloseServiceHandle(scm);
  return result;
}

int UninstallService() {
  SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_ALL_ACCESS);
  if (!scm) {
    return 1;
  }
  SC_HANDLE svc = OpenServiceW(scm, kServiceName, SERVICE_ALL_ACCESS);
  int result = 0;
  if (svc) {
    SERVICE_STATUS status = {};
    ControlService(svc, SERVICE_CONTROL_STOP, &status);
    DeleteService(svc);
    CloseServiceHandle(svc);
  }
  CloseServiceHandle(scm);
  return result;
}

bool HasArg(const std::wstring& needle) {
  int argc = 0;
  LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (!argv) {
    return false;
  }
  bool found = false;
  for (int i = 1; i < argc; ++i) {
    if (needle == argv[i]) {
      found = true;
      break;
    }
  }
  LocalFree(argv);
  return found;
}

}  // namespace

bool HandleCommandLine(int* exit_code) {
  if (HasArg(L"--rd-worker")) {
    *exit_code = RunWorker();
    return true;
  }
  if (HasArg(L"--rd-service")) {
    *exit_code = RunServiceDispatcher();
    return true;
  }
  if (HasArg(L"--rd-install")) {
    *exit_code = InstallService();
    return true;
  }
  if (HasArg(L"--rd-uninstall")) {
    *exit_code = UninstallService();
    return true;
  }
  return false;
}

}  // namespace rd_service
