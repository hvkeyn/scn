#ifndef RUNNER_WIN7_WEBRTC_ENABLE_H_
#define RUNNER_WIN7_WEBRTC_ENABLE_H_

#include <flutter/plugin_registry.h>

namespace win7_webrtc {

// Registers flutter_webrtc only. Safe to call after first frame when the user
// explicitly enables Remote Desktop. Returns true if newly registered or
// already registered.
bool Enable(flutter::PluginRegistry* registry);

bool IsEnabled();

}  // namespace win7_webrtc

#endif  // RUNNER_WIN7_WEBRTC_ENABLE_H_
