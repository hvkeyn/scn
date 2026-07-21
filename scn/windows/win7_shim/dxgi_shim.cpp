// Win7 shim: forwards DXGI factory creation to system dxgi.dll when available.
// On Windows 7 blocks factory creation so ANGLE fails cleanly and Flutter
// falls back to software rendering instead of crashing inside ntdll.

#include "win7_shim_common.h"

#include <dxgi.h>

namespace {

using CreateDXGIFactory1Fn = HRESULT(WINAPI*)(REFIID, void**);
using CreateDXGIFactoryFn = HRESULT(WINAPI*)(REFIID, void**);
using CreateDXGIFactory2Fn = HRESULT(WINAPI*)(UINT, REFIID, void**);

CreateDXGIFactory1Fn RealCreateDXGIFactory1() {
  static CreateDXGIFactory1Fn fn = reinterpret_cast<CreateDXGIFactory1Fn>(
      GetProcAddress(scn_win7::LoadSystemModule(L"dxgi.dll"),
                     "CreateDXGIFactory1"));
  return fn;
}

CreateDXGIFactoryFn RealCreateDXGIFactory() {
  static CreateDXGIFactoryFn fn = reinterpret_cast<CreateDXGIFactoryFn>(
      GetProcAddress(scn_win7::LoadSystemModule(L"dxgi.dll"),
                     "CreateDXGIFactory"));
  return fn;
}

CreateDXGIFactory2Fn RealCreateDXGIFactory2() {
  static CreateDXGIFactory2Fn fn = reinterpret_cast<CreateDXGIFactory2Fn>(
      GetProcAddress(scn_win7::LoadSystemModule(L"dxgi.dll"),
                     "CreateDXGIFactory2"));
  return fn;
}

HRESULT BlockedFactory(const wchar_t* api_name) {
  wchar_t msg[128] = {};
  wsprintfW(msg, L"scn_dxgi: blocked %s (Win7 software rendering)", api_name);
  scn_win7::LogShim(msg);
  return DXGI_ERROR_UNSUPPORTED;
}

}  // namespace

extern "C" {

HRESULT WINAPI ScnCreateDXGIFactory1(REFIID riid, void** factory) {
  if (!factory) {
    return E_INVALIDARG;
  }
  *factory = nullptr;

  if (scn_win7::ShouldBlockGpuOnWin7()) {
    return BlockedFactory(L"CreateDXGIFactory1");
  }

  if (const CreateDXGIFactory1Fn create1 = RealCreateDXGIFactory1()) {
    return create1(riid, factory);
  }
  if (const CreateDXGIFactoryFn create0 = RealCreateDXGIFactory()) {
    return create0(riid, factory);
  }
  return HRESULT_FROM_WIN32(ERROR_PROC_NOT_FOUND);
}

HRESULT WINAPI ScnCreateDXGIFactory(REFIID riid, void** factory) {
  if (!factory) {
    return E_INVALIDARG;
  }
  *factory = nullptr;

  if (scn_win7::ShouldBlockGpuOnWin7()) {
    return BlockedFactory(L"CreateDXGIFactory");
  }

  if (const CreateDXGIFactoryFn create0 = RealCreateDXGIFactory()) {
    return create0(riid, factory);
  }
  return HRESULT_FROM_WIN32(ERROR_PROC_NOT_FOUND);
}

HRESULT WINAPI ScnCreateDXGIFactory2(UINT flags, REFIID riid, void** factory) {
  if (!factory) {
    return E_INVALIDARG;
  }
  *factory = nullptr;

  if (scn_win7::ShouldBlockGpuOnWin7()) {
    return BlockedFactory(L"CreateDXGIFactory2");
  }

  if (const CreateDXGIFactory2Fn create2 = RealCreateDXGIFactory2()) {
    return create2(flags, riid, factory);
  }
  // Win7 system dxgi often has no CreateDXGIFactory2 — fall back.
  if (const CreateDXGIFactory1Fn create1 = RealCreateDXGIFactory1()) {
    return create1(riid, factory);
  }
  return HRESULT_FROM_WIN32(ERROR_PROC_NOT_FOUND);
}

}  // extern "C"
