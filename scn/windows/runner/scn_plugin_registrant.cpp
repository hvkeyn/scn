#include <flutter/plugin_registry.h>

#include "win7_crash_log.h"
#include "win7_env.h"

#include <screen_retriever/screen_retriever_plugin.h>
#include <window_manager/window_manager_plugin.h>
#include <flutter_webrtc/flutter_web_r_t_c_plugin.h>
#include <tray_manager/tray_manager_plugin.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  if (win7_env::IsWindows7()) {
    // flutter_webrtc / tray / window_manager crash Win7 after first frame
    // (libwebrtc worker threads). Build 192 proved: no plugins = stable.
    // Remote Desktop needs a separate delayed WebRTC path later.
    win7_crash_log::Write(L"RegisterPlugins win7 (none — webrtc crashes)");
    return;
  }

  FlutterWebRTCPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterWebRTCPlugin"));
  ScreenRetrieverPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("ScreenRetrieverPlugin"));
  TrayManagerPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("TrayManagerPlugin"));
  WindowManagerPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("WindowManagerPlugin"));
}
