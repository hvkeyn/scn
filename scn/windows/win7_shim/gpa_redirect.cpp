// Win7 GPA redirect + TLS hook for flutter_windows.dll (see inject_flutter_tls.py).

#include <windows.h>
#include <winnt.h>

#include <cctype>
#include <cstdint>
#include <cstdio>

extern "C" FARPROC WINAPI ScnHookedGetProcAddress(HMODULE module, LPCSTR name);
extern "C" BOOL WINAPI ScnPatchFlutterGetProcAddress(HMODULE module);

namespace scn_gpa {
namespace {

using GetProcAddressFn = FARPROC(WINAPI*)(HMODULE, LPCSTR);

GetProcAddressFn g_real_get_proc_address = nullptr;
HMODULE g_system_ntdll = nullptr;

bool EqualsIgnoreCase(const char* a, const char* b) {
  if (!a || !b) {
    return false;
  }
  while (*a && *b) {
    if (tolower(static_cast<unsigned char>(*a)) !=
        tolower(static_cast<unsigned char>(*b))) {
      return false;
    }
    ++a;
    ++b;
  }
  return *a == *b;
}

bool IsWindows7() {
  static bool win7 = []() {
    OSVERSIONINFOEXW info = {};
    info.dwOSVersionInfoSize = sizeof(info);
    using RtlGetVersionFn = LONG(WINAPI*)(PRTL_OSVERSIONINFOW);
    const auto rtl_get_version = reinterpret_cast<RtlGetVersionFn>(
        ::GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "RtlGetVersion"));
    if (!rtl_get_version ||
        rtl_get_version(reinterpret_cast<PRTL_OSVERSIONINFOW>(&info)) != 0) {
      return false;
    }
    return info.dwMajorVersion == 6 && info.dwMinorVersion == 1;
  }();
  return win7;
}

void LogLine(const wchar_t* message) {
  wchar_t temp[MAX_PATH] = {};
  if (GetTempPathW(MAX_PATH, temp) == 0) {
    return;
  }
  wchar_t path[MAX_PATH] = {};
  wsprintfW(path, L"%sscn_win7.log", temp);
  FILE* log = nullptr;
  if (_wfopen_s(&log, path, L"a, ccs=UTF-8") != 0 || !log) {
    return;
  }
  fwprintf(log, L"%s\r\n", message);
  fflush(log);
  fclose(log);
}

FARPROC* FindImportSlot(HMODULE module, const char* import_dll, const char* symbol) {
  auto* base = reinterpret_cast<uint8_t*>(module);
  auto* dos = reinterpret_cast<IMAGE_DOS_HEADER*>(base);
  if (dos->e_magic != IMAGE_DOS_SIGNATURE) {
    return nullptr;
  }
  auto* nt = reinterpret_cast<IMAGE_NT_HEADERS64*>(base + dos->e_lfanew);
  if (nt->Signature != IMAGE_NT_SIGNATURE) {
    return nullptr;
  }

  const auto& import_dir =
      nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
  if (import_dir.VirtualAddress == 0) {
    return nullptr;
  }

  auto* import_desc = reinterpret_cast<IMAGE_IMPORT_DESCRIPTOR*>(
      base + import_dir.VirtualAddress);
  for (; import_desc->Name != 0; ++import_desc) {
    const char* dll_name = reinterpret_cast<const char*>(base + import_desc->Name);
    if (!EqualsIgnoreCase(dll_name, import_dll)) {
      continue;
    }

    auto* thunk = reinterpret_cast<IMAGE_THUNK_DATA64*>(
        base + import_desc->FirstThunk);
    auto* orig = reinterpret_cast<IMAGE_THUNK_DATA64*>(
        base + (import_desc->OriginalFirstThunk
                    ? import_desc->OriginalFirstThunk
                    : import_desc->FirstThunk));

    for (; orig->u1.AddressOfData != 0; ++orig, ++thunk) {
      if (orig->u1.Ordinal & IMAGE_ORDINAL_FLAG64) {
        continue;
      }
      const auto* import_by_name = reinterpret_cast<IMAGE_IMPORT_BY_NAME*>(
          base + orig->u1.AddressOfData);
      if (!EqualsIgnoreCase(reinterpret_cast<const char*>(import_by_name->Name),
                            symbol)) {
        continue;
      }
      return reinterpret_cast<FARPROC*>(&thunk->u1.Function);
    }
  }
  return nullptr;
}

bool EnsureGlobals() {
  if (!g_system_ntdll) {
    g_system_ntdll = GetModuleHandleW(L"ntdll.dll");
  }
  if (!g_real_get_proc_address) {
    const HMODULE kernel32 = GetModuleHandleW(L"kernel32.dll");
    if (!kernel32) {
      return false;
    }
    g_real_get_proc_address = reinterpret_cast<GetProcAddressFn>(
        ::GetProcAddress(kernel32, "GetProcAddress"));
  }
  return g_system_ntdll && g_real_get_proc_address;
}

bool PatchModuleGetProcAddress(HMODULE module) {
  if (!IsWindows7() || !module) {
    return true;
  }

  if (!EnsureGlobals()) {
    return false;
  }

  FARPROC* slot = FindImportSlot(module, "KERNEL32.dll", "GetProcAddress");
  if (!slot) {
    slot = FindImportSlot(module, "kernel32.dll", "GetProcAddress");
  }
  if (!slot) {
    slot = FindImportSlot(module, "scn_kernel32.dll", "GetProcAddress");
  }
  if (!slot) {
    LogLine(L"gpa patch: skipped (no GetProcAddress import)");
    return true;
  }

  if (*slot == reinterpret_cast<FARPROC>(ScnHookedGetProcAddress)) {
    return true;
  }

  DWORD old_protect = 0;
  if (!VirtualProtect(slot, sizeof(FARPROC), PAGE_READWRITE, &old_protect)) {
    return false;
  }
  *slot = reinterpret_cast<FARPROC>(ScnHookedGetProcAddress);
  VirtualProtect(slot, sizeof(FARPROC), old_protect, &old_protect);
  FlushInstructionCache(GetCurrentProcess(), slot, sizeof(FARPROC));
  return true;
}

}  // namespace
}  // namespace scn_gpa

extern "C" FARPROC WINAPI ScnHookedGetProcAddress(HMODULE module, LPCSTR name) {
  using namespace scn_gpa;
  if (!EnsureGlobals()) {
    return nullptr;
  }

  if (IsWindows7() && name && module == g_system_ntdll) {
    if (EqualsIgnoreCase(name, "RtlAddGrowableFunctionTable") ||
        EqualsIgnoreCase(name, "RtlDeleteGrowableFunctionTable") ||
        EqualsIgnoreCase(name, "RtlGrowFunctionTable")) {
      const HMODULE scn_ntdll = GetModuleHandleW(L"scn_ntdll.dll");
      if (scn_ntdll) {
        if (FARPROC proc = g_real_get_proc_address(scn_ntdll, name)) {
          wchar_t msg[160] = {};
          wsprintfW(msg, L"gpa redirect %hs -> scn_ntdll", name);
          LogLine(msg);
          return proc;
        }
      }
    }
  }

  // ANGLE dynamically resolves D3D11/DXGI entry points via GetProcAddress.
  // On Win7 redirect them to our shims so ANGLE init fails cleanly and Flutter
  // falls back to software rendering instead of crashing inside the GPU stack.
  if (IsWindows7() && name) {
    const wchar_t* shim_dll = nullptr;
    if (EqualsIgnoreCase(name, "D3D11CreateDevice")) {
      shim_dll = L"scn_d3d11.dll";
    } else if (EqualsIgnoreCase(name, "CreateDXGIFactory1") ||
               EqualsIgnoreCase(name, "CreateDXGIFactory") ||
               EqualsIgnoreCase(name, "CreateDXGIFactory2")) {
      shim_dll = L"scn_dxgi.dll";
    }
    if (shim_dll) {
      if (const HMODULE shim = GetModuleHandleW(shim_dll)) {
        if (FARPROC proc = g_real_get_proc_address(shim, name)) {
          wchar_t msg[160] = {};
          wsprintfW(msg, L"gpa redirect %hs -> %s", name, shim_dll);
          LogLine(msg);
          return proc;
        }
      }
    }
  }

  return g_real_get_proc_address(module, name);
}

extern "C" void NTAPI ScnWin7TlsCallback(PVOID module, DWORD reason, PVOID /*reserved*/) {
  if (reason != DLL_PROCESS_ATTACH) {
    return;
  }
  if (!ScnPatchFlutterGetProcAddress(static_cast<HMODULE>(module))) {
    scn_gpa::LogLine(L"gpa tls patch failed");
    return;
  }
  scn_gpa::LogLine(L"gpa tls patch ok");
}

extern "C" BOOL WINAPI ScnPatchFlutterGetProcAddress(HMODULE module) {
  return scn_gpa::PatchModuleGetProcAddress(module) ? TRUE : FALSE;
}
