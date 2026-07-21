#ifndef RUNNER_WIN7_RD_CHANNEL_H_
#define RUNNER_WIN7_RD_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/plugin_registry.h>

#include <memory>

namespace win7_rd_channel {

// Dart MethodChannel "scn/win7_rd": enableWebRtc / isWebRtcEnabled.
void Setup(flutter::BinaryMessenger* messenger,
           flutter::PluginRegistry* registry);
void Shutdown();

}  // namespace win7_rd_channel

#endif  // RUNNER_WIN7_RD_CHANNEL_H_
