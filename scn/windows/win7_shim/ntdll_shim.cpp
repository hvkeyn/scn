// Win7 shim for ntdll exports missing on Windows 7.

#include <windows.h>
#include <winnt.h>

#include <cstring>

using NtStatus = LONG;
constexpr NtStatus kStatusSuccess = 0x00000000L;
constexpr NtStatus kStatusInvalidParameter = 0xC000000DL;

using VerSetConditionMaskFn = ULONGLONG(WINAPI*)(ULONGLONG, DWORD, BYTE);
using RtlAddFunctionTableFn = BOOLEAN(WINAPI*)(PRUNTIME_FUNCTION, DWORD, DWORD64);
using RtlDeleteFunctionTableFn = BOOLEAN(WINAPI*)(PRUNTIME_FUNCTION);

struct ScnDynamicFunctionTable {
  PRUNTIME_FUNCTION function_table;
  DWORD entry_count;
  DWORD maximum_size;
  ULONG_PTR range_base;
  ULONG_PTR range_end;
  bool registered;
};

namespace {

VerSetConditionMaskFn RealVerSetConditionMask() {
  static VerSetConditionMaskFn fn = reinterpret_cast<VerSetConditionMaskFn>(
      GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "VerSetConditionMask"));
  return fn;
}

RtlAddFunctionTableFn RealRtlAddFunctionTable() {
  static RtlAddFunctionTableFn fn = reinterpret_cast<RtlAddFunctionTableFn>(
      GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "RtlAddFunctionTable"));
  return fn;
}

RtlDeleteFunctionTableFn RealRtlDeleteFunctionTable() {
  static RtlDeleteFunctionTableFn fn = reinterpret_cast<RtlDeleteFunctionTableFn>(
      GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "RtlDeleteFunctionTable"));
  return fn;
}

extern "C" void ScnWin7InstallGetProcAddressHook();

bool RegisterTable(ScnDynamicFunctionTable* table) {
  if (!table || table->registered || table->entry_count == 0 ||
      !table->function_table) {
    return true;
  }
  const RtlAddFunctionTableFn rtl_add = RealRtlAddFunctionTable();
  if (!rtl_add) {
    return false;
  }
  table->registered =
      rtl_add(table->function_table, table->entry_count, table->range_base) != FALSE;
  return table->registered;
}

void UnregisterTable(ScnDynamicFunctionTable* table) {
  if (!table || !table->registered || !table->function_table) {
    return;
  }
  const RtlDeleteFunctionTableFn rtl_del = RealRtlDeleteFunctionTable();
  if (rtl_del) {
    rtl_del(table->function_table);
  }
  table->registered = false;
}

}  // namespace

extern "C" {

NtStatus WINAPI ScnRtlAddGrowableFunctionTable(
    PVOID* dynamic_table,
    PRUNTIME_FUNCTION function_table,
    DWORD entry_count,
    DWORD maximum_size,
    ULONG_PTR range_base,
    ULONG_PTR range_end) {
  if (!dynamic_table || !function_table || maximum_size == 0 ||
      entry_count > maximum_size) {
    return kStatusInvalidParameter;
  }

  auto* table = static_cast<ScnDynamicFunctionTable*>(
      HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(ScnDynamicFunctionTable)));
  if (!table) {
    return kStatusInvalidParameter;
  }

  const SIZE_T bytes = static_cast<SIZE_T>(maximum_size) * sizeof(RUNTIME_FUNCTION);
  table->function_table = static_cast<PRUNTIME_FUNCTION>(
      HeapAlloc(GetProcessHeap(), 0, bytes));
  if (!table->function_table) {
    HeapFree(GetProcessHeap(), 0, table);
    return kStatusInvalidParameter;
  }

  std::memcpy(table->function_table, function_table,
              static_cast<SIZE_T>(entry_count) * sizeof(RUNTIME_FUNCTION));
  table->entry_count = entry_count;
  table->maximum_size = maximum_size;
  table->range_base = range_base;
  table->range_end = range_end;

  RegisterTable(table);
  *dynamic_table = table;
  return kStatusSuccess;
}

NtStatus WINAPI ScnRtlDeleteGrowableFunctionTable(PVOID dynamic_table) {
  if (!dynamic_table) {
    return kStatusInvalidParameter;
  }

  auto* table = static_cast<ScnDynamicFunctionTable*>(dynamic_table);
  UnregisterTable(table);
  if (table->function_table) {
    HeapFree(GetProcessHeap(), 0, table->function_table);
  }
  HeapFree(GetProcessHeap(), 0, table);
  return kStatusSuccess;
}

NtStatus WINAPI ScnRtlGrowFunctionTable(PVOID dynamic_table, DWORD entry_count) {
  if (!dynamic_table || entry_count == 0) {
    return kStatusInvalidParameter;
  }

  auto* table = static_cast<ScnDynamicFunctionTable*>(dynamic_table);
  if (entry_count > table->maximum_size) {
    return kStatusInvalidParameter;
  }

  UnregisterTable(table);
  table->entry_count = entry_count;
  RegisterTable(table);
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

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID /*reserved*/) {
  if (reason == DLL_PROCESS_ATTACH) {
    DisableThreadLibraryCalls(instance);
    ScnWin7InstallGetProcAddressHook();
  }
  return TRUE;
}
