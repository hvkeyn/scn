// Win7 shim for ntdll exports missing on Windows 7.
// Forwards to native ntdll when RtlAddGrowableFunctionTable exists (Win8+).
// On Win7 registers unwind tables via RtlAddFunctionTable (Vista+).

#include <windows.h>
#include <winnt.h>

#include <stdio.h>

using NtStatus = DWORD;
constexpr NtStatus kStatusSuccess = 0;
constexpr NtStatus kStatusInvalidParameter = 0xC000000DL;
constexpr NtStatus kStatusNoMemory = 0xC0000017L;

using VerSetConditionMaskFn = ULONGLONG(WINAPI*)(ULONGLONG, DWORD, BYTE);
using RtlAddGrowableFunctionTableFn = NtStatus(WINAPI*)(
    PVOID*, PRUNTIME_FUNCTION, DWORD, DWORD, ULONG_PTR, ULONG_PTR);
using RtlDeleteGrowableFunctionTableFn = NtStatus(WINAPI*)(PVOID);
using RtlGrowFunctionTableFn = NtStatus(WINAPI*)(PVOID, DWORD);
using RtlAddFunctionTableFn = BOOLEAN(WINAPI*)(PRUNTIME_FUNCTION, DWORD,
                                               DWORD64);
using RtlDeleteFunctionTableFn = BOOLEAN(WINAPI*)(PRUNTIME_FUNCTION);

namespace {

struct GrowableTableRecord {
  PRUNTIME_FUNCTION function_table;
  DWORD entry_count;
  DWORD maximum_entry_count;
  ULONG_PTR range_base;
};

HMODULE RealNtdllModule() {
  static HMODULE module = GetModuleHandleW(L"ntdll.dll");
  return module;
}

template <typename Fn>
Fn ResolveNtdllProc(const char* name) {
  const HMODULE module = RealNtdllModule();
  if (!module) {
    return nullptr;
  }
  return reinterpret_cast<Fn>(GetProcAddress(module, name));
}

void LogShim(const wchar_t* message) {
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

VerSetConditionMaskFn RealVerSetConditionMask() {
  static VerSetConditionMaskFn fn = reinterpret_cast<VerSetConditionMaskFn>(
      GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "VerSetConditionMask"));
  return fn;
}

RtlAddGrowableFunctionTableFn RealRtlAddGrowableFunctionTable() {
  static RtlAddGrowableFunctionTableFn fn =
      ResolveNtdllProc<RtlAddGrowableFunctionTableFn>(
          "RtlAddGrowableFunctionTable");
  return fn;
}

RtlDeleteGrowableFunctionTableFn RealRtlDeleteGrowableFunctionTable() {
  static RtlDeleteGrowableFunctionTableFn fn =
      ResolveNtdllProc<RtlDeleteGrowableFunctionTableFn>(
          "RtlDeleteGrowableFunctionTable");
  return fn;
}

RtlGrowFunctionTableFn RealRtlGrowFunctionTable() {
  static RtlGrowFunctionTableFn fn =
      ResolveNtdllProc<RtlGrowFunctionTableFn>("RtlGrowFunctionTable");
  return fn;
}

RtlAddFunctionTableFn RealRtlAddFunctionTable() {
  static RtlAddFunctionTableFn fn =
      ResolveNtdllProc<RtlAddFunctionTableFn>("RtlAddFunctionTable");
  return fn;
}

RtlDeleteFunctionTableFn RealRtlDeleteFunctionTable() {
  static RtlDeleteFunctionTableFn fn =
      ResolveNtdllProc<RtlDeleteFunctionTableFn>("RtlDeleteFunctionTable");
  return fn;
}

bool RegisterStaticFunctionTable(GrowableTableRecord* record) {
  const RtlAddFunctionTableFn rtl_add = RealRtlAddFunctionTable();
  if (!rtl_add || !record) {
    return false;
  }
  return rtl_add(record->function_table, record->entry_count,
                 static_cast<DWORD64>(record->range_base)) != FALSE;
}

bool UnregisterStaticFunctionTable(GrowableTableRecord* record) {
  const RtlDeleteFunctionTableFn rtl_delete = RealRtlDeleteFunctionTable();
  if (!rtl_delete || !record || !record->function_table) {
    return false;
  }
  return rtl_delete(record->function_table) != FALSE;
}

GrowableTableRecord* AllocRecord(PRUNTIME_FUNCTION function_table,
                                 DWORD entry_count,
                                 DWORD maximum_size,
                                 ULONG_PTR range_base) {
  void* memory = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY,
                           sizeof(GrowableTableRecord));
  if (!memory) {
    return nullptr;
  }
  auto* record = static_cast<GrowableTableRecord*>(memory);
  record->function_table = function_table;
  record->entry_count = entry_count;
  record->maximum_entry_count = maximum_size;
  record->range_base = range_base;
  return record;
}

void FreeRecord(GrowableTableRecord* record) {
  if (record) {
    HeapFree(GetProcessHeap(), 0, record);
  }
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
  if (const RtlAddGrowableFunctionTableFn rtl_add =
          RealRtlAddGrowableFunctionTable()) {
    return rtl_add(dynamic_table, function_table, entry_count, maximum_size,
                   range_base, range_end);
  }

  if (!dynamic_table || !function_table || maximum_size == 0 ||
      entry_count > maximum_size) {
    return kStatusInvalidParameter;
  }

  GrowableTableRecord* record =
      AllocRecord(function_table, entry_count, maximum_size, range_base);
  if (!record) {
    return kStatusNoMemory;
  }

  if (!RegisterStaticFunctionTable(record)) {
    wchar_t msg[160] = {};
    wsprintfW(msg,
              L"scn_ntdll: RtlAddFunctionTable failed err=%lu "
              L"(entries=%lu base=0x%p)",
              GetLastError(), entry_count,
              reinterpret_cast<void*>(range_base));
    LogShim(msg);
    FreeRecord(record);
    return kStatusInvalidParameter;
  }

  wchar_t msg[160] = {};
  wsprintfW(msg,
            L"scn_ntdll: RtlAddFunctionTable ok entries=%lu base=0x%p end=0x%p",
            entry_count, reinterpret_cast<void*>(range_base),
            reinterpret_cast<void*>(range_end));
  LogShim(msg);

  *dynamic_table = record;
  return kStatusSuccess;
}

NtStatus WINAPI ScnRtlDeleteGrowableFunctionTable(PVOID dynamic_table) {
  if (const RtlDeleteGrowableFunctionTableFn rtl_delete =
          RealRtlDeleteGrowableFunctionTable()) {
    return rtl_delete(dynamic_table);
  }

  if (!dynamic_table) {
    return kStatusInvalidParameter;
  }

  auto* record = static_cast<GrowableTableRecord*>(dynamic_table);
  if (!UnregisterStaticFunctionTable(record)) {
    wchar_t msg[128] = {};
    wsprintfW(msg, L"scn_ntdll: RtlDeleteFunctionTable failed err=%lu",
              GetLastError());
    LogShim(msg);
  }
  FreeRecord(record);
  return kStatusSuccess;
}

NtStatus WINAPI ScnRtlGrowFunctionTable(PVOID dynamic_table, DWORD entry_count) {
  if (const RtlGrowFunctionTableFn rtl_grow = RealRtlGrowFunctionTable()) {
    return rtl_grow(dynamic_table, entry_count);
  }

  if (!dynamic_table || entry_count == 0) {
    return kStatusInvalidParameter;
  }

  auto* record = static_cast<GrowableTableRecord*>(dynamic_table);
  if (entry_count > record->maximum_entry_count) {
    return kStatusInvalidParameter;
  }

  if (entry_count == record->entry_count) {
    return kStatusSuccess;
  }

  if (!UnregisterStaticFunctionTable(record)) {
    return kStatusInvalidParameter;
  }

  record->entry_count = entry_count;
  if (!RegisterStaticFunctionTable(record)) {
    LogShim(L"scn_ntdll: RtlGrowFunctionTable re-register failed");
    return kStatusInvalidParameter;
  }

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
  }
  return TRUE;
}
