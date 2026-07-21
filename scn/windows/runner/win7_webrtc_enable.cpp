#include "win7_webrtc_enable.h"

#include "win7_crash_log.h"
#include "win7_env.h"
#include "win7_iat_patch.h"

#include <flutter_webrtc/flutter_web_r_t_c_plugin.h>

namespace win7_webrtc {
namespace {

bool g_enabled = false;

}  // namespace

bool IsEnabled() { return g_enabled; }

bool Enable(flutter::PluginRegistry* registry) {
  if (g_enabled) {
    win7_crash_log::Write(L"win7 webrtc already enabled");
    return true;
  }
  if (!registry) {
    win7_crash_log::Write(L"win7 webrtc enable: null registry");
    return false;
  }

  win7_crash_log::Write(L"win7 webrtc enable: registering FlutterWebRTCPlugin");
  // Delay-load of flutter_webrtc_plugin.dll happens here.
  FlutterWebRTCPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterWebRTCPlugin"));
  // GetHostNameW only — DXGI hooks come later via applyWebRtcGpuHooks.
  win7_iat::ApplyWebRtcHostnameHooks();
  g_enabled = true;
  win7_crash_log::Write(L"win7 webrtc enable: ok (hostname hooks, GPU deferred)");
  return true;
}

}  // namespace win7_webrtc
