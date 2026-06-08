#include "win7_prereq.h"

#include <shlobj.h>
#include <urlmon.h>
#include <windows.h>

#include <string>
#include <vector>

#pragma comment(lib, "urlmon.lib")

namespace win7_prereq {
namespace {

constexpr wchar_t kVcRedistUrl[] =
    L"https://aka.ms/vs/17/release/vc_redist.x64.exe";
constexpr wchar_t kUcrtMsuUrl[] =
    L"https://download.microsoft.com/download/9/0/F/"
    L"90F025C-F1AA-40B0-B1A9-CEB3E206E72C/"
    L"windows6.1-kb2999226-x64.msu";
constexpr wchar_t kUcrtDownloadPage[] =
    L"https://www.microsoft.com/download/details.aspx?id=49093";
constexpr wchar_t kVcRedistDownloadPage[] =
    L"https://aka.ms/vs/17/release/vc_redist.x64.exe";

bool IsOsVersion(DWORD major, DWORD minor) {
  OSVERSIONINFOEXW info = {};
  info.dwOSVersionInfoSize = sizeof(info);
  info.dwMajorVersion = major;
  info.dwMinorVersion = minor;

  DWORDLONG mask = 0;
  VER_SET_CONDITION(mask, VER_MAJORVERSION, VER_EQUAL);
  VER_SET_CONDITION(mask, VER_MINORVERSION, VER_EQUAL);

  return VerifyVersionInfoW(&info, VER_MAJORVERSION | VER_MINORVERSION,
                            mask) != FALSE;
}

bool RegistryDwordIsOne(HKEY root, const wchar_t* subkey,
                       const wchar_t* value_name) {
  HKEY key = nullptr;
  if (RegOpenKeyExW(root, subkey, 0, KEY_READ | KEY_WOW64_64KEY, &key) !=
      ERROR_SUCCESS) {
    return false;
  }

  DWORD value = 0;
  DWORD size = sizeof(value);
  const LSTATUS status =
      RegQueryValueExW(key, value_name, nullptr, nullptr,
                       reinterpret_cast<LPBYTE>(&value), &size);
  RegCloseKey(key);
  return status == ERROR_SUCCESS && value == 1;
}

bool IsVcRedistInstalled() {
  if (RegistryDwordIsOne(
          HKEY_LOCAL_MACHINE,
          L"SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\x64",
          L"Installed")) {
    return true;
  }
  if (RegistryDwordIsOne(
          HKEY_LOCAL_MACHINE,
          L"SOFTWARE\\WOW6432Node\\Microsoft\\VisualStudio\\14.0\\VC\\"
          L"Runtimes\\x64",
          L"Installed")) {
    return true;
  }

  wchar_t sys_dir[MAX_PATH] = {};
  if (GetSystemDirectoryW(sys_dir, MAX_PATH) == 0) {
    return false;
  }
  std::wstring path = std::wstring(sys_dir) + L"\\vcruntime140.dll";
  return GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES;
}

bool IsUcrtInstalled() {
  if (RegistryDwordIsOne(
          HKEY_LOCAL_MACHINE,
          L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\"
          L"Uninstall\\{D5F0FC36-2112-4C2A-8A7F-E7F8D5D5B5D5}",
          L"Installed")) {
    return true;
  }

  wchar_t sys_dir[MAX_PATH] = {};
  if (GetSystemDirectoryW(sys_dir, MAX_PATH) == 0) {
    return false;
  }
  const std::wstring ucrt_path =
      std::wstring(sys_dir) + L"\\api-ms-win-crt-runtime-l1-1-0.dll";
  const bool exists =
      GetFileAttributesW(ucrt_path.c_str()) != INVALID_FILE_ATTRIBUTES;
  return exists;
}

std::wstring TempSetupDir() {
  wchar_t temp[MAX_PATH] = {};
  GetTempPathW(MAX_PATH, temp);
  std::wstring dir = std::wstring(temp) + L"scn_win7_setup\\";
  CreateDirectoryW(dir.c_str(), nullptr);
  return dir;
}

bool DownloadToFile(const wchar_t* url, const std::wstring& dest) {
  DeleteFileW(dest.c_str());
  const HRESULT hr =
      URLDownloadToFileW(nullptr, url, dest.c_str(), 0, nullptr);
  return SUCCEEDED(hr) && GetFileAttributesW(dest.c_str()) != INVALID_FILE_ATTRIBUTES;
}

DWORD RunProcess(const std::wstring& command, DWORD timeout_ms) {
  STARTUPINFOW si = {};
  si.cb = sizeof(si);
  PROCESS_INFORMATION pi = {};

  std::vector<wchar_t> cmd_buf(command.begin(), command.end());
  cmd_buf.push_back(L'\0');
  if (!CreateProcessW(nullptr, cmd_buf.data(), nullptr, nullptr, FALSE, 0,
                      nullptr, nullptr, &si, &pi)) {
    return static_cast<DWORD>(-1);
  }

  WaitForSingleObject(pi.hProcess, timeout_ms);
  DWORD exit_code = static_cast<DWORD>(-1);
  GetExitCodeProcess(pi.hProcess, &exit_code);
  CloseHandle(pi.hProcess);
  CloseHandle(pi.hThread);
  return exit_code;
}

void OpenUrl(const wchar_t* url) {
  ShellExecuteW(nullptr, L"open", url, nullptr, nullptr, SW_SHOWNORMAL);
}

int ShowMissingDialog(bool need_ucrt, bool need_vc) {
  std::wstring body =
      L"Для работы SCN на Windows 7 нужны системные компоненты:\n\n";
  if (need_ucrt) {
    body += L"• Universal C Runtime (KB2999226)\n";
  }
  if (need_vc) {
    body += L"• Microsoft Visual C++ 2015–2022 (x64)\n";
  }
  body +=
      L"\nSCN может скачать и установить их автоматически "
      L"(потребуются права администратора).\n\n"
      L"Установить сейчас?";

  return MessageBoxW(
      nullptr, body.c_str(), L"SCN — установка компонентов Windows 7",
      MB_YESNOCANCEL | MB_ICONINFORMATION | MB_TASKMODAL | MB_SETFOREGROUND);
}

bool InstallUcrt(const std::wstring& dir) {
  const std::wstring msu_path = dir + L"windows6.1-kb2999226-x64.msu";
  if (!DownloadToFile(kUcrtMsuUrl, msu_path)) {
    OpenUrl(kUcrtDownloadPage);
    return false;
  }

  const std::wstring cmd =
      L"wusa.exe \"" + msu_path + L"\" /quiet /norestart";
  const DWORD code = RunProcess(cmd, 10 * 60 * 1000);
  return code == 0 || code == 3010;  // success or reboot required
}

bool InstallVcRedist(const std::wstring& dir) {
  const std::wstring exe_path = dir + L"vc_redist.x64.exe";
  if (!DownloadToFile(kVcRedistUrl, exe_path)) {
    OpenUrl(kVcRedistDownloadPage);
    return false;
  }

  const std::wstring cmd =
      L"\"" + exe_path + L"\" /install /quiet /norestart";
  const DWORD code = RunProcess(cmd, 10 * 60 * 1000);
  return code == 0 || code == 3010 || code == 1638;  // already installed
}

}  // namespace

bool IsWindows7() {
  return IsOsVersion(6, 1);
}

bool EnsurePrerequisites() {
  if (!IsWindows7()) {
    return true;
  }

  const bool need_ucrt = !IsUcrtInstalled();
  const bool need_vc = !IsVcRedistInstalled();
  if (!need_ucrt && !need_vc) {
    return true;
  }

  const int choice = ShowMissingDialog(need_ucrt, need_vc);
  if (choice == IDCANCEL) {
    return false;
  }
  if (choice == IDNO) {
    MessageBoxW(
        nullptr,
        L"SCN запускается без установки компонентов. "
        L"При ошибках DLL установите KB2999226 и VC++ Redistributable вручную.",
        L"SCN", MB_OK | MB_ICONWARNING | MB_TASKMODAL);
    return true;
  }

  const std::wstring dir = TempSetupDir();
  bool ok = true;

  if (need_ucrt) {
    if (!InstallUcrt(dir)) {
      ok = false;
    }
  }
  if (need_vc && (ok || !need_ucrt)) {
    if (!InstallVcRedist(dir)) {
      ok = false;
    }
  }

  if (!ok) {
    const int retry = MessageBoxW(
        nullptr,
        L"Не удалось установить все компоненты автоматически.\n"
        L"Открыть страницы загрузки Microsoft?",
        L"SCN", MB_YESNO | MB_ICONWARNING | MB_TASKMODAL);
    if (retry == IDYES) {
      if (need_ucrt) {
        OpenUrl(kUcrtDownloadPage);
      }
      if (need_vc) {
        OpenUrl(kVcRedistDownloadPage);
      }
    }
    return true;  // let user try to run anyway after manual install
  }

  MessageBoxW(nullptr,
              L"Компоненты установлены. Если Windows запросит перезагрузку — "
              L"выполните её и снова запустите SCN.",
              L"SCN", MB_OK | MB_ICONINFORMATION | MB_TASKMODAL);
  return true;
}

}  // namespace win7_prereq
