#include "win7_mesh_signal.h"

#include "win7_crash_log.h"
#include "win7_env.h"

#include <windows.h>

namespace win7_mesh_signal {
namespace {

bool AppendFileName(wchar_t* out, size_t out_chars, const wchar_t* name) {
  if (wcslen(out) + wcslen(name) + 2 >= out_chars) {
    return false;
  }
  wcscat_s(out, out_chars, name);
  return true;
}

bool AppendSignalFileName(wchar_t* out, size_t out_chars) {
  return AppendFileName(out, out_chars, L"scn_win7_mesh_ok");
}

bool AppendStartMeshFileName(wchar_t* out, size_t out_chars) {
  return AppendFileName(out, out_chars, L"scn_win7_start_mesh");
}

bool TempSignalPath(wchar_t* out, size_t out_chars) {
  if (GetTempPathW(static_cast<DWORD>(out_chars), out) == 0) {
    return false;
  }
  return AppendSignalFileName(out, out_chars);
}

bool ExeDirPath(wchar_t* out, size_t out_chars) {
  if (GetModuleFileNameW(nullptr, out, static_cast<DWORD>(out_chars)) == 0) {
    return false;
  }
  wchar_t* last_slash = wcsrchr(out, L'\\');
  if (last_slash == nullptr) {
    return false;
  }
  *(last_slash + 1) = L'\0';
  return true;
}

bool ExeSignalPath(wchar_t* out, size_t out_chars) {
  if (!ExeDirPath(out, out_chars)) {
    return false;
  }
  return AppendSignalFileName(out, out_chars);
}

bool ExeStartMeshPath(wchar_t* out, size_t out_chars) {
  if (!ExeDirPath(out, out_chars)) {
    return false;
  }
  return AppendStartMeshFileName(out, out_chars);
}

void WriteSignalFile(const wchar_t* path) {
  HANDLE file = CreateFileW(path, GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                            FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    wchar_t msg[MAX_PATH + 64] = {};
    wsprintfW(msg, L"mesh signal create failed: %s err=%lu", path,
              GetLastError());
    win7_crash_log::Write(msg);
    return;
  }
  const char payload[] = "1";
  DWORD written = 0;
  WriteFile(file, payload, static_cast<DWORD>(sizeof(payload) - 1), &written,
            nullptr);
  CloseHandle(file);
  win7_crash_log::Write(path);
  win7_crash_log::Write(L"mesh signal file written");
}

}  // namespace

void ClearSignalFile() {
  if (!win7_env::IsWindows7()) {
    return;
  }
  wchar_t path[MAX_PATH] = {};
  if (TempSignalPath(path, MAX_PATH)) {
    DeleteFileW(path);
  }
  if (ExeSignalPath(path, MAX_PATH)) {
    DeleteFileW(path);
  }
  if (ExeStartMeshPath(path, MAX_PATH)) {
    DeleteFileW(path);
  }
}

void SignalNativeFirstFrame() {
  if (!win7_env::IsWindows7()) {
    return;
  }
  wchar_t path[MAX_PATH] = {};
  if (TempSignalPath(path, MAX_PATH)) {
    WriteSignalFile(path);
  } else {
    win7_crash_log::Write(L"mesh signal temp path failed");
  }
  if (ExeSignalPath(path, MAX_PATH)) {
    WriteSignalFile(path);
  } else {
    win7_crash_log::Write(L"mesh signal exe path failed");
  }
}

void WriteStartMeshSignal() {
  if (!win7_env::IsWindows7()) {
    return;
  }
  wchar_t path[MAX_PATH] = {};
  if (ExeStartMeshPath(path, MAX_PATH)) {
    WriteSignalFile(path);
  } else {
    win7_crash_log::Write(L"mesh start signal exe path failed");
  }
}

}  // namespace win7_mesh_signal
