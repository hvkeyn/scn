#include "win7_iat_patch.h"
#include "win7_env.h"

#include <delayimp.h>
#include <windows.h>

namespace {

FARPROC WINAPI Win7DelayLoadNotifyHook(unsigned notify, PDelayLoadInfo info) {
  if (notify != dliNotePreLoadLibrary || !info || !info->szDll) {
    return nullptr;
  }

  if (!win7_env::IsWindows7()) {
    return nullptr;
  }

  wchar_t wide[MAX_PATH] = {};
  MultiByteToWideChar(CP_ACP, 0, info->szDll, -1, wide, MAX_PATH);
  HMODULE module = win7_iat::LoadModuleWithWin7Imports(wide);
  return reinterpret_cast<FARPROC>(module);
}

}  // namespace

extern "C" const PfnDliHook __pfnDliNotifyHook2 = Win7DelayLoadNotifyHook;
