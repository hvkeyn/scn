#include "win7_iat_patch.h"

#include "win7_crash_log.h"
#include "win7_env.h"

#include <windows.h>

#include <cctype>
#include <cstring>

namespace win7_iat {
namespace {

struct RedirectRule {
  const char* source_dll;
  const char* target_dll;
  const char* symbol;
};

constexpr RedirectRule kRedirects[] = {
    {"WS2_32.dll", "scn_ws2.dll", "GetHostNameW"},
    {"ntdll.dll", "scn_ntdll.dll", "RtlAddGrowableFunctionTable"},
    {"ntdll.dll", "scn_ntdll.dll", "RtlDeleteGrowableFunctionTable"},
    {"ntdll.dll", "scn_ntdll.dll", "RtlGrowFunctionTable"},
    {"ntdll.dll", "scn_ntdll.dll", "VerSetConditionMask"},
    {"KERNEL32.dll", "scn_kernel32.dll", "CompareStringEx"},
    {"KERNEL32.dll", "scn_kernel32.dll", "LCMapStringEx"},
    {"KERNEL32.dll", "scn_kernel32.dll", "GetFileInformationByHandleEx"},
    {"KERNEL32.dll", "scn_ntdll.dll", "VerSetConditionMask"},
    {"dxgi.dll", "scn_dxgi.dll", "CreateDXGIFactory1"},
    {"dxgi.dll", "scn_dxgi.dll", "CreateDXGIFactory"},
    {"d3d11.dll", "scn_d3d11.dll", "D3D11CreateDevice"},
};

constexpr DWORD kLoadDeferred = 0x00000001;  // DONT_RESOLVE_DLL_REFERENCES

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

const RedirectRule* FindRedirect(const char* source_dll, const char* symbol) {
  for (const RedirectRule& rule : kRedirects) {
    if (EqualsIgnoreCase(rule.source_dll, source_dll) &&
        std::strcmp(rule.symbol, symbol) == 0) {
      return &rule;
    }
  }
  return nullptr;
}

bool GetExeDirectory(wchar_t* out, size_t out_chars) {
  if (GetModuleFileNameW(nullptr, out, static_cast<DWORD>(out_chars)) == 0) {
    return false;
  }
  wchar_t* slash = wcsrchr(out, L'\\');
  if (!slash) {
    return false;
  }
  slash[1] = L'\0';
  return true;
}

bool BuildModulePath(const wchar_t* module_name, wchar_t* out, size_t out_chars) {
  wchar_t dir[MAX_PATH] = {};
  if (!GetExeDirectory(dir, MAX_PATH)) {
    return false;
  }
  if (wcslen(dir) + wcslen(module_name) + 1 >= out_chars) {
    return false;
  }
  wcscpy_s(out, out_chars, dir);
  wcscat_s(out, out_chars, module_name);
  return true;
}

HMODULE LoadShimModule(const char* target_dll) {
  wchar_t wide[MAX_PATH] = {};
  MultiByteToWideChar(CP_ACP, 0, target_dll, -1, wide, MAX_PATH);
  HMODULE module = GetModuleHandleW(wide);
  if (!module) {
    module = LoadLibraryW(wide);
  }
  return module;
}

FARPROC ResolveShimExport(HMODULE shim, const char* symbol) {
  FARPROC address = GetProcAddress(shim, symbol);
  if (!address && std::strcmp(symbol, "GetHostNameW") == 0) {
    address = GetProcAddress(shim, "ScnGetHostNameW");
  }
  return address;
}

FARPROC ResolveImport(const char* source_dll, const char* symbol) {
  if (const RedirectRule* rule = FindRedirect(source_dll, symbol)) {
    HMODULE shim = LoadShimModule(rule->target_dll);
    if (!shim) {
      return nullptr;
    }
    return ResolveShimExport(shim, rule->symbol);
  }

  HMODULE source = GetModuleHandleA(source_dll);
  if (!source) {
    wchar_t wide[MAX_PATH] = {};
    MultiByteToWideChar(CP_ACP, 0, source_dll, -1, wide, MAX_PATH);
    source = LoadLibraryW(wide);
  }
  if (!source) {
    return nullptr;
  }
  return GetProcAddress(source, symbol);
}

bool WriteIatThunk(IMAGE_THUNK_DATA* iat, ULONG_PTR value) {
  DWORD old_protect = 0;
  if (!VirtualProtect(&iat->u1.Function, sizeof(ULONG_PTR), PAGE_READWRITE,
                      &old_protect)) {
    return false;
  }
  iat->u1.Function = value;
  VirtualProtect(&iat->u1.Function, sizeof(ULONG_PTR), old_protect,
                 &old_protect);
  return true;
}

void LogImportFailure(const char* source_dll, const char* symbol) {
  wchar_t msg[256] = {};
  wchar_t source_wide[128] = {};
  wchar_t symbol_wide[128] = {};
  MultiByteToWideChar(CP_ACP, 0, source_dll, -1, source_wide, 128);
  MultiByteToWideChar(CP_ACP, 0, symbol, -1, symbol_wide, 128);
  wsprintfW(msg, L"IAT resolve failed %s!%s", source_wide, symbol_wide);
  win7_crash_log::Write(msg);
}

bool ResolveImports(HMODULE module) {
  const auto* base = reinterpret_cast<const BYTE*>(module);
  const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
  if (dos->e_magic != IMAGE_DOS_SIGNATURE) {
    return false;
  }
  const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS*>(base + dos->e_lfanew);
  if (nt->Signature != IMAGE_NT_SIGNATURE) {
    return false;
  }

  const IMAGE_DATA_DIRECTORY* import_dir =
      &nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
  if (import_dir->VirtualAddress == 0) {
    return true;
  }

  auto* import_desc = reinterpret_cast<IMAGE_IMPORT_DESCRIPTOR*>(
      const_cast<BYTE*>(base + import_dir->VirtualAddress));
  for (; import_desc->Name; ++import_desc) {
    const char* source_dll =
        reinterpret_cast<const char*>(base + import_desc->Name);
    auto* lookup = reinterpret_cast<IMAGE_THUNK_DATA*>(
        const_cast<BYTE*>(base + import_desc->OriginalFirstThunk));
    auto* iat = reinterpret_cast<IMAGE_THUNK_DATA*>(
        const_cast<BYTE*>(base + import_desc->FirstThunk));
    if (!import_desc->OriginalFirstThunk) {
      lookup = iat;
    }

    for (; lookup->u1.AddressOfData; ++lookup, ++iat) {
      const char* symbol = nullptr;
      if (IMAGE_SNAP_BY_ORDINAL(lookup->u1.Ordinal)) {
        if (iat->u1.Function != 0) {
          continue;
        }
        HMODULE source = GetModuleHandleA(source_dll);
        if (!source) {
          source = LoadLibraryA(source_dll);
        }
        if (!source) {
          LogImportFailure(source_dll, "#ordinal");
          return false;
        }
        FARPROC address = GetProcAddress(
            source, reinterpret_cast<LPCSTR>(lookup->u1.Ordinal & 0xFFFF));
        if (!address) {
          LogImportFailure(source_dll, "#ordinal");
          return false;
        }
        if (!WriteIatThunk(iat, reinterpret_cast<ULONG_PTR>(address))) {
          return false;
        }
        continue;
      }

      const auto* import_by_name = reinterpret_cast<IMAGE_IMPORT_BY_NAME*>(
          const_cast<BYTE*>(base + lookup->u1.AddressOfData));
      symbol = reinterpret_cast<const char*>(import_by_name->Name);

      const bool redirected = FindRedirect(source_dll, symbol) != nullptr;
      if (!redirected && iat->u1.Function != 0) {
        continue;
      }

      FARPROC address = ResolveImport(source_dll, symbol);
      if (!address) {
        LogImportFailure(source_dll, symbol);
        return false;
      }
      if (!WriteIatThunk(iat, reinterpret_cast<ULONG_PTR>(address))) {
        return false;
      }
    }
  }
  return true;
}

bool RunDllMainAttach(HMODULE module) {
  const auto* base = reinterpret_cast<const BYTE*>(module);
  const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
  const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS*>(base + dos->e_lfanew);
  if (nt->OptionalHeader.AddressOfEntryPoint == 0) {
    return true;
  }

  using DllMainFn = BOOL(WINAPI*)(HINSTANCE, DWORD, LPVOID);
  auto* entry = reinterpret_cast<DllMainFn>(
      const_cast<BYTE*>(base + nt->OptionalHeader.AddressOfEntryPoint));
  return entry(reinterpret_cast<HINSTANCE>(module), DLL_PROCESS_ATTACH, nullptr) != FALSE;
}

}  // namespace

HMODULE LoadModuleWithWin7Imports(const wchar_t* module_name) {
  HMODULE existing = GetModuleHandleW(module_name);
  if (existing) {
    return existing;
  }

  wchar_t path[MAX_PATH] = {};
  if (!BuildModulePath(module_name, path, MAX_PATH)) {
    win7_crash_log::Write(L"IAT module path failed");
    return nullptr;
  }

  HMODULE module = LoadLibraryExW(path, nullptr, kLoadDeferred);
  if (!module) {
    wchar_t msg[256] = {};
    wsprintfW(msg, L"deferred load failed %s err=%lu", path, GetLastError());
    win7_crash_log::Write(msg);
    return nullptr;
  }

  if (!ResolveImports(module)) {
    win7_crash_log::Write(L"IAT resolve failed");
    FreeLibrary(module);
    return nullptr;
  }

  if (!RunDllMainAttach(module)) {
    win7_crash_log::Write(L"DllMain failed");
    FreeLibrary(module);
    return nullptr;
  }

  wchar_t msg[256] = {};
  wsprintfW(msg, L"%s loaded with Win7 IAT", module_name);
  win7_crash_log::Write(msg);
  return module;
}

bool PatchProcessImports() {
  if (!win7_env::IsWindows7()) {
    return true;
  }

  win7_crash_log::Write(L"IAT patch begin");

  static const wchar_t* kModules[] = {
      L"flutter_windows.dll",
      L"libwebrtc.dll",
      L"flutter_webrtc_plugin.dll",
      L"screen_retriever_plugin.dll",
      L"tray_manager_plugin.dll",
      L"window_manager_plugin.dll",
  };

  for (const wchar_t* module : kModules) {
    if (!LoadModuleWithWin7Imports(module)) {
      win7_crash_log::Write(L"IAT patch failed");
      return false;
    }
  }

  win7_crash_log::Write(L"IAT patch done");
  return true;
}

}  // namespace win7_iat
