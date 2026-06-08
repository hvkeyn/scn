// Win7 shim: forwards DXGI factory creation to system dxgi.dll with fallback.

#include <windows.h>

#include <dxgi.h>

namespace {

using CreateDXGIFactory1Fn = HRESULT(WINAPI*)(REFIID, void**);
using CreateDXGIFactoryFn = HRESULT(WINAPI*)(REFIID, void**);

HMODULE SystemDxgiModule() {
  static HMODULE module = LoadLibraryW(L"dxgi.dll");
  return module;
}

CreateDXGIFactory1Fn RealCreateDXGIFactory1() {
  static CreateDXGIFactory1Fn fn = reinterpret_cast<CreateDXGIFactory1Fn>(
      GetProcAddress(SystemDxgiModule(), "CreateDXGIFactory1"));
  return fn;
}

CreateDXGIFactoryFn RealCreateDXGIFactory() {
  static CreateDXGIFactoryFn fn = reinterpret_cast<CreateDXGIFactoryFn>(
      GetProcAddress(SystemDxgiModule(), "CreateDXGIFactory"));
  return fn;
}

}  // namespace

extern "C" {

HRESULT WINAPI ScnCreateDXGIFactory1(REFIID riid, void** factory) {
  if (!factory) {
    return E_INVALIDARG;
  }
  *factory = nullptr;

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

  if (const CreateDXGIFactoryFn create0 = RealCreateDXGIFactory()) {
    return create0(riid, factory);
  }
  return HRESULT_FROM_WIN32(ERROR_PROC_NOT_FOUND);
}

}  // extern "C"
