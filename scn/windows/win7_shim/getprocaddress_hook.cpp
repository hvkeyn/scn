// x64 inline hook for GetProcAddress — redirects Win8+ ntdll Rtl* lookups.

#include <windows.h>

#include <cstdint>
#include <cstring>

using NtStatus = LONG;

extern "C" {
NtStatus WINAPI ScnRtlAddGrowableFunctionTable(PVOID*, PRUNTIME_FUNCTION, DWORD,
                                               DWORD, ULONG_PTR, ULONG_PTR);
NtStatus WINAPI ScnRtlDeleteGrowableFunctionTable(PVOID);
NtStatus WINAPI ScnRtlGrowFunctionTable(PVOID, DWORD);
}

using GetProcAddressFn = FARPROC(WINAPI*)(HMODULE, LPCSTR);

namespace {

GetProcAddressFn g_original_get_proc_address = nullptr;
uint8_t g_target_saved[16] = {};
void* g_target = nullptr;
constexpr SIZE_T kPatchSize = 14;

bool IsNamedImport(LPCSTR name) {
  return name != nullptr && reinterpret_cast<ULONG_PTR>(name) > 0xFFFF;
}

FARPROC RedirectNtdllProc(LPCSTR name) {
  if (!IsNamedImport(name)) {
    return nullptr;
  }
  if (std::strcmp(name, "RtlAddGrowableFunctionTable") == 0) {
    return reinterpret_cast<FARPROC>(ScnRtlAddGrowableFunctionTable);
  }
  if (std::strcmp(name, "RtlDeleteGrowableFunctionTable") == 0) {
    return reinterpret_cast<FARPROC>(ScnRtlDeleteGrowableFunctionTable);
  }
  if (std::strcmp(name, "RtlGrowFunctionTable") == 0) {
    return reinterpret_cast<FARPROC>(ScnRtlGrowFunctionTable);
  }
  return nullptr;
}

FARPROC WINAPI HookedGetProcAddress(HMODULE module, LPCSTR name) {
  if (IsNamedImport(name)) {
    if (const FARPROC redirected = RedirectNtdllProc(name)) {
      return redirected;
    }
  }
  return g_original_get_proc_address(module, name);
}

bool InstallGetProcAddressHook() {
  if (g_original_get_proc_address) {
    return true;
  }

  HMODULE kernel32 = GetModuleHandleW(L"kernel32.dll");
  if (!kernel32) {
    return false;
  }

  g_target = reinterpret_cast<void*>(GetProcAddress(kernel32, "GetProcAddress"));
  if (!g_target) {
    return false;
  }

  std::memcpy(g_target_saved, g_target, kPatchSize);

  void* trampoline = VirtualAlloc(nullptr, 64, MEM_COMMIT | MEM_RESERVE,
                                  PAGE_EXECUTE_READWRITE);
  if (!trampoline) {
    return false;
  }

  std::memcpy(trampoline, g_target_saved, kPatchSize);
  auto* jump_back = reinterpret_cast<uint8_t*>(trampoline) + kPatchSize;
  jump_back[0] = 0xFF;
  jump_back[1] = 0x25;
  *reinterpret_cast<uint32_t*>(jump_back + 2) = 0;
  *reinterpret_cast<uint64_t*>(jump_back + 6) =
      reinterpret_cast<uint64_t>(reinterpret_cast<uint8_t*>(g_target) + kPatchSize);

  g_original_get_proc_address =
      reinterpret_cast<GetProcAddressFn>(trampoline);

  DWORD old_protect = 0;
  if (!VirtualProtect(g_target, kPatchSize, PAGE_EXECUTE_READWRITE, &old_protect)) {
    VirtualFree(trampoline, 0, MEM_RELEASE);
    g_original_get_proc_address = nullptr;
    return false;
  }

  auto* patch = reinterpret_cast<uint8_t*>(g_target);
  patch[0] = 0xFF;
  patch[1] = 0x25;
  *reinterpret_cast<uint32_t*>(patch + 2) = 0;
  *reinterpret_cast<uint64_t*>(patch + 6) =
      reinterpret_cast<uint64_t>(&HookedGetProcAddress);

  VirtualProtect(g_target, kPatchSize, old_protect, &old_protect);
  FlushInstructionCache(GetCurrentProcess(), g_target, kPatchSize);
  return true;
}

}  // namespace

extern "C" void ScnWin7InstallGetProcAddressHook() {
  InstallGetProcAddressHook();
}
