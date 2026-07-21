// Win7 shim for D3D11CreateDevice.
// On Windows 7 returns failure so ANGLE/EGL init fails cleanly and Flutter uses
// software rendering. On Win8+ forwards to system d3d11.dll.

#include "win7_shim_common.h"

#include <d3d11.h>

namespace {

using D3D11CreateDeviceFn = HRESULT(WINAPI*)(
    IDXGIAdapter*, D3D_DRIVER_TYPE, HMODULE, UINT, const D3D_FEATURE_LEVEL*, UINT,
    UINT, ID3D11Device**, D3D_FEATURE_LEVEL*, ID3D11DeviceContext**);

D3D11CreateDeviceFn RealD3D11CreateDevice() {
  static D3D11CreateDeviceFn fn = reinterpret_cast<D3D11CreateDeviceFn>(
      GetProcAddress(scn_win7::LoadSystemModule(L"d3d11.dll"),
                     "D3D11CreateDevice"));
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
  if (scn_win7::ShouldBlockGpuOnWin7()) {
    scn_win7::LogShim(L"scn_d3d11: blocked D3D11CreateDevice (Win7 software rendering)");
    return E_FAIL;
  }

  const D3D11CreateDeviceFn create = RealD3D11CreateDevice();
  if (!create) {
    return HRESULT_FROM_WIN32(ERROR_PROC_NOT_FOUND);
  }
  return create(adapter, driver_type, software, flags, feature_levels,
                feature_level_count, sdk_version, device, obtained_feature_level,
                immediate_context);
}

}  // extern "C"
