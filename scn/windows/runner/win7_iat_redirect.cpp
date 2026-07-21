#include "win7_iat_redirect.h"

#include "win7_crash_log.h"
#include "win7_env.h"

#include <windows.h>
#include <winnt.h>

#include <cctype>
#include <cstdint>

namespace win7_iat_redirect {
namespace {

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

bool RedirectOne(HMODULE module,
                 const char* import_dll,
                 const char* symbol,
                 HMODULE shim_module,
                 const char* shim_export) {
  FARPROC* slot = FindImportSlot(module, import_dll, symbol);
  if (!slot || !shim_module) {
    return false;
  }

  const FARPROC replacement = GetProcAddress(shim_module, shim_export);
  if (!replacement) {
    return false;
  }
  if (*slot == replacement) {
    return true;
  }

  DWORD old_protect = 0;
  if (!VirtualProtect(slot, sizeof(FARPROC), PAGE_READWRITE, &old_protect)) {
    return false;
  }
  *slot = replacement;
  VirtualProtect(slot, sizeof(FARPROC), old_protect, &old_protect);
  FlushInstructionCache(GetCurrentProcess(), slot, sizeof(FARPROC));
  return true;
}

void LogRedirect(const char* import_dll, const char* symbol, bool ok) {
  wchar_t msg[160] = {};
  wsprintfW(msg, L"iat redirect %hs!%hs %s", import_dll, symbol,
            ok ? L"ok" : L"failed");
  win7_crash_log::Write(msg);
}

}  // namespace

bool PatchModuleHostnameImports(HMODULE module) {
  if (!win7_env::IsWindows7() || !module) {
    return true;
  }

  const HMODULE scn_ws2 = GetModuleHandleW(L"scn_ws2.dll");
  const struct {
    const char* import_dll;
    const char* symbol;
    HMODULE shim;
    const char* export_name;
  } redirects[] = {
      {"scn_ws2.dll", "GetHostNameW", scn_ws2, "GetHostNameW"},
      {"WS2_32.dll", "GetHostNameW", scn_ws2, "GetHostNameW"},
      {"ws2_32.dll", "GetHostNameW", scn_ws2, "GetHostNameW"},
  };

  bool any = false;
  for (const auto& entry : redirects) {
    if (!FindImportSlot(module, entry.import_dll, entry.symbol)) {
      continue;
    }
    const bool ok = RedirectOne(module, entry.import_dll, entry.symbol,
                                entry.shim, entry.export_name);
    LogRedirect(entry.import_dll, entry.symbol, ok);
    any = any || ok;
  }
  return any;
}

bool PatchModuleGpuImports(HMODULE module) {
  if (!win7_env::IsWindows7() || !module) {
    return true;
  }

  const HMODULE scn_dxgi = GetModuleHandleW(L"scn_dxgi.dll");
  const HMODULE scn_d3d11 = GetModuleHandleW(L"scn_d3d11.dll");

  // Redirect static GPU imports. libwebrtc.dll imports d3d11/dxgi directly;
  // flutter_windows.dll imports dxgi and resolves d3d11 via GetProcAddress.
  const struct {
    const char* import_dll;
    const char* symbol;
    HMODULE shim;
    const char* export_name;
  } redirects[] = {
      {"dxgi.dll", "CreateDXGIFactory1", scn_dxgi, "CreateDXGIFactory1"},
      {"dxgi.dll", "CreateDXGIFactory", scn_dxgi, "CreateDXGIFactory"},
      {"dxgi.dll", "CreateDXGIFactory2", scn_dxgi, "CreateDXGIFactory2"},
      {"scn_dxgi.dll", "CreateDXGIFactory1", scn_dxgi, "CreateDXGIFactory1"},
      {"scn_dxgi.dll", "CreateDXGIFactory", scn_dxgi, "CreateDXGIFactory"},
      {"scn_dxgi.dll", "CreateDXGIFactory2", scn_dxgi, "CreateDXGIFactory2"},
      {"d3d11.dll", "D3D11CreateDevice", scn_d3d11, "D3D11CreateDevice"},
      {"scn_d3d11.dll", "D3D11CreateDevice", scn_d3d11, "D3D11CreateDevice"},
  };

  bool any = false;
  for (const auto& entry : redirects) {
    if (!FindImportSlot(module, entry.import_dll, entry.symbol)) {
      continue;
    }
    const bool ok = RedirectOne(module, entry.import_dll, entry.symbol,
                                entry.shim, entry.export_name);
    LogRedirect(entry.import_dll, entry.symbol, ok);
    any = any || ok;
  }
  return any;
}

}  // namespace win7_iat_redirect
