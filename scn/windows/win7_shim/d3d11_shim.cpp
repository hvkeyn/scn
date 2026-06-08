// Win7 shim: forwards D3D11CreateDevice to system d3d11.dll when available.

#include <windows.h>

#include <d3d11.h>

namespace {

using D3D11CreateDeviceFn = HRESULT(WINAPI*)(
    IDXGIAdapter*, D3D_DRIVER_TYPE, HMODULE, UINT, const D3D_FEATURE_LEVEL*, UINT,
    UINT, ID3D11Device**, D3D_FEATURE_LEVEL*, ID3D11DeviceContext**);

D3D11CreateDeviceFn RealD3D11CreateDevice() {
  static D3D11CreateDeviceFn fn = reinterpret_cast<D3D11CreateDeviceFn>([]() -> FARPROC {
    HMODULE module = LoadLibraryW(L"d3d11.dll");
    if (!module) {
      return nullptr;
    }
    return GetProcAddress(module, "D3D11CreateDevice");
  }());
  return fn;
}

}  // namespace

extern "C" {

HRESULT WINAPI ScnD3D11CreateDevice(
    IDXGIAdapter* adapter,
    D3D_DRIVER_TYPE driver_type,
    HMODULE software,
    UINT flags,
    const D3D_FEATURE_LEVEL* feature_levels,
    UINT feature_level_count,
    UINT sdk_version,
    ID3D11Device** device,
    D3D_FEATURE_LEVEL* obtained_feature_level,
    ID3D11DeviceContext** immediate_context) {
  const D3D11CreateDeviceFn create = RealD3D11CreateDevice();
  if (!create) {
    return HRESULT_FROM_WIN32(ERROR_PROC_NOT_FOUND);
  }
  return create(adapter, driver_type, software, flags, feature_levels,
                feature_level_count, sdk_version, device, obtained_feature_level,
                immediate_context);
}

}  // extern "C"
