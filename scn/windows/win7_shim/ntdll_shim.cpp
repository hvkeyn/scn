// Win7 shim for ntdll exports missing on Windows 7.

#include <windows.h>

using NtStatus = LONG;
constexpr NtStatus kStatusSuccess = 0x00000000L;
constexpr NtStatus kStatusInvalidParameter = 0xC000000DL;

typedef struct _SCN_RUNTIME_FUNCTION {
  ULONG BeginAddress;
  ULONG EndAddress;
  ULONG UnwindData;
} SCN_RUNTIME_FUNCTION, *PSCN_RUNTIME_FUNCTION;

using VerSetConditionMaskFn = ULONGLONG(WINAPI*)(ULONGLONG, DWORD, BYTE);

namespace {

VerSetConditionMaskFn RealVerSetConditionMask() {
  static VerSetConditionMaskFn fn = reinterpret_cast<VerSetConditionMaskFn>(
      GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "VerSetConditionMask"));
  return fn;
}

}  // namespace

extern "C" {

NtStatus WINAPI ScnRtlAddGrowableFunctionTable(
    PVOID* dynamic_table,
    PSCN_RUNTIME_FUNCTION /*function_table*/,
    DWORD /*entry_count*/,
    DWORD /*maximum_size*/,
    ULONG_PTR /*range_base*/,
    ULONG_PTR /*range_end*/) {
  if (!dynamic_table) {
    return kStatusInvalidParameter;
  }
  static char dummy_handles[8][sizeof(PVOID)] = {};
  static unsigned index = 0;
  *dynamic_table =
      &dummy_handles[(index++) % (sizeof(dummy_handles) / sizeof(dummy_handles[0]))];
  return kStatusSuccess;
}

NtStatus WINAPI ScnRtlDeleteGrowableFunctionTable(PVOID /*dynamic_table*/) {
  return kStatusSuccess;
}

ULONGLONG WINAPI ScnVerSetConditionMask(ULONGLONG condition_mask,
                                      DWORD type_mask,
                                      BYTE condition) {
  const VerSetConditionMaskFn fn = RealVerSetConditionMask();
  if (!fn) {
    return condition_mask;
  }
  return fn(condition_mask, type_mask, condition);
}

}  // extern "C"
