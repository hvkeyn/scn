#include "win7_flutter_diag.h"

#include "win7_crash_log.h"

#include <windows.h>

namespace win7_flutter_diag {
namespace {

using FlutterDesktopEngineRef = void*;

struct FlutterDesktopEngineProperties {
  const wchar_t* assets_path;
  const wchar_t* icu_data_path;
  const wchar_t* aot_library_path;
  const char* dart_entrypoint;
  int dart_entrypoint_argc;
  const char** dart_entrypoint_argv;
};

using CreateEngineFn = FlutterDesktopEngineRef (*)(const FlutterDesktopEngineProperties*);
using DestroyEngineFn = bool (*)(FlutterDesktopEngineRef);

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

void LogPathEntry(const wchar_t* label, const wchar_t* path) {
  WIN32_FILE_ATTRIBUTE_DATA attrs = {};
  if (!GetFileAttributesExW(path, GetFileExInfoStandard, &attrs)) {
    wchar_t msg[512] = {};
    wsprintfW(msg, L"%s missing err=%lu", label, GetLastError());
    win7_crash_log::Write(msg);
    return;
  }

  ULARGE_INTEGER size = {};
  size.LowPart = attrs.nFileSizeLow;
  size.HighPart = attrs.nFileSizeHigh;
  wchar_t msg[512] = {};
  wsprintfW(msg, L"%s ok size=%I64u", label, size.QuadPart);
  win7_crash_log::Write(msg);
}

void BuildDataPath(const wchar_t* suffix, wchar_t* out, size_t out_chars) {
  wchar_t dir[MAX_PATH] = {};
  if (!GetExeDirectory(dir, MAX_PATH)) {
    out[0] = L'\0';
    return;
  }
  wsprintfW(out, L"%sdata\\%s", dir, suffix);
}

CreateEngineFn ResolveCreateEngine() {
  const HMODULE module = GetModuleHandleW(L"flutter_windows.dll");
  if (!module) {
    return nullptr;
  }
  return reinterpret_cast<CreateEngineFn>(
      GetProcAddress(module, "FlutterDesktopEngineCreate"));
}

DestroyEngineFn ResolveDestroyEngine() {
  const HMODULE module = GetModuleHandleW(L"flutter_windows.dll");
  if (!module) {
    return nullptr;
  }
  return reinterpret_cast<DestroyEngineFn>(
      GetProcAddress(module, "FlutterDesktopEngineDestroy"));
}

}  // namespace

void LogDataBundle() {
  wchar_t path[MAX_PATH] = {};

  BuildDataPath(L"app.so", path, MAX_PATH);
  LogPathEntry(L"data\\app.so", path);

  BuildDataPath(L"icudtl.dat", path, MAX_PATH);
  LogPathEntry(L"data\\icudtl.dat", path);

  BuildDataPath(L"flutter_assets\\AssetManifest.bin", path, MAX_PATH);
  LogPathEntry(L"data\\flutter_assets\\AssetManifest.bin", path);
}

void ProbeEngineCreate() {
  const CreateEngineFn create_engine = ResolveCreateEngine();
  const DestroyEngineFn destroy_engine = ResolveDestroyEngine();
  if (!create_engine || !destroy_engine) {
    win7_crash_log::Write(L"probe engine exports missing");
    return;
  }

  wchar_t assets[MAX_PATH] = {};
  wchar_t icu[MAX_PATH] = {};
  wchar_t aot[MAX_PATH] = {};
  BuildDataPath(L"flutter_assets", assets, MAX_PATH);
  BuildDataPath(L"icudtl.dat", icu, MAX_PATH);
  BuildDataPath(L"app.so", aot, MAX_PATH);

  FlutterDesktopEngineProperties props = {};
  props.assets_path = assets;
  props.icu_data_path = icu;
  props.aot_library_path = aot;

  win7_crash_log::Write(L"probe FlutterDesktopEngineCreate start");
  wchar_t env_buf[256] = {};
  if (GetEnvironmentVariableW(L"FLUTTER_ENGINE_SWITCHES", env_buf,
                              static_cast<DWORD>(sizeof(env_buf) / sizeof(env_buf[0]))) > 0) {
    win7_crash_log::Write(L"env FLUTTER_ENGINE_SWITCHES set");
  } else {
    win7_crash_log::Write(L"env FLUTTER_ENGINE_SWITCHES missing");
  }
  if (GetEnvironmentVariableW(L"FLUTTER_ENGINE_SWITCH_1", env_buf,
                              static_cast<DWORD>(sizeof(env_buf) / sizeof(env_buf[0]))) > 0) {
    wchar_t msg[384] = {};
    wsprintfW(msg, L"env switch1=%s", env_buf);
    win7_crash_log::Write(msg);
  }

  FlutterDesktopEngineRef engine = create_engine(&props);
  if (!engine) {
    win7_crash_log::Write(L"probe FlutterDesktopEngineCreate failed");
    return;
  }

  win7_crash_log::Write(L"probe FlutterDesktopEngineCreate ok");
  if (destroy_engine(engine)) {
    win7_crash_log::Write(L"probe FlutterDesktopEngineDestroy ok");
  } else {
    win7_crash_log::Write(L"probe FlutterDesktopEngineDestroy failed");
  }
}

}  // namespace win7_flutter_diag
