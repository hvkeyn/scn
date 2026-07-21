#include "win7_rd_channel.h"

#include <windows.h>
#include <shellapi.h>

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <string>

#include "win7_crash_log.h"
#include "win7_env.h"
#include "win7_iat_patch.h"
#include "win7_rd_capture.h"
#include "win7_webrtc_enable.h"

namespace win7_rd_channel {
namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodChannel;
using flutter::MethodCall;
using flutter::MethodResult;

std::unique_ptr<MethodChannel<EncodableValue>> g_channel;
flutter::PluginRegistry* g_registry = nullptr;

int ReadIntArg(const EncodableMap* args, const char* key, int fallback) {
  if (!args) {
    return fallback;
  }
  const auto it = args->find(EncodableValue(key));
  if (it == args->end()) {
    return fallback;
  }
  if (const auto* i = std::get_if<int32_t>(&it->second)) {
    return *i;
  }
  if (const auto* i = std::get_if<int64_t>(&it->second)) {
    return static_cast<int>(*i);
  }
  return fallback;
}

std::string ReadStringArg(const EncodableMap* args, const char* key) {
  if (!args) {
    return {};
  }
  const auto it = args->find(EncodableValue(key));
  if (it == args->end()) {
    return {};
  }
  if (const auto* s = std::get_if<std::string>(&it->second)) {
    return *s;
  }
  return {};
}

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) {
    return {};
  }
  const int n = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(),
                                    static_cast<int>(utf8.size()), nullptr, 0);
  if (n <= 0) {
    return {};
  }
  std::wstring out(static_cast<size_t>(n), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()),
                      out.data(), n);
  return out;
}

bool ShowNotifyBalloon(const std::string& title_utf8,
                       const std::string& body_utf8) {
  static NOTIFYICONDATAW nid = {};
  static bool added = false;

  const std::wstring title = Utf8ToWide(title_utf8);
  const std::wstring body = Utf8ToWide(body_utf8);

  ZeroMemory(&nid, sizeof(nid));
  nid.cbSize = sizeof(nid);
  nid.hWnd = GetForegroundWindow();
  if (!nid.hWnd) {
    nid.hWnd = GetDesktopWindow();
  }
  nid.uID = 0x53434E42;  // 'SCNB'
  nid.uFlags = NIF_INFO | NIF_ICON | NIF_TIP;
  nid.dwInfoFlags = NIIF_INFO;
  nid.uTimeout = 4000;
  nid.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
  wcsncpy_s(nid.szTip, L"SCN", _TRUNCATE);
  wcsncpy_s(nid.szInfoTitle,
            title.empty() ? L"SCN" : title.c_str(), _TRUNCATE);
  wcsncpy_s(nid.szInfo,
            body.empty() ? L"Remote desktop connected" : body.c_str(),
            _TRUNCATE);

  if (!added) {
    if (!Shell_NotifyIconW(NIM_ADD, &nid)) {
      return false;
    }
    added = true;
  }
  return Shell_NotifyIconW(NIM_MODIFY, &nid) == TRUE;
}

void HandleMethodCall(const MethodCall<EncodableValue>& call,
                      std::unique_ptr<MethodResult<EncodableValue>> result) {
  const std::string& method = call.method_name();
  if (method == "isWebRtcEnabled") {
    result->Success(EncodableValue(win7_webrtc::IsEnabled()));
    return;
  }
  if (method == "enableWebRtc") {
    if (!win7_env::IsWindows7()) {
      result->Success(EncodableValue(true));
      return;
    }
    win7_crash_log::Write(L"win7_rd channel: enableWebRtc");
    const bool ok = win7_webrtc::Enable(g_registry);
    if (ok) {
      result->Success(EncodableValue(true));
    } else {
      result->Error("webrtc_enable_failed", "Failed to register WebRTC plugin");
    }
    return;
  }
  if (method == "applyWebRtcGpuHooks") {
    if (!win7_env::IsWindows7()) {
      result->Success(EncodableValue(true));
      return;
    }
    win7_crash_log::Write(L"win7_rd channel: applyWebRtcGpuHooks");
    win7_iat::ApplyWebRtcGpuHooks();
    result->Success(EncodableValue(true));
    return;
  }
  if (method == "listMonitors") {
    const auto monitors = win7_rd_capture::ListMonitors();
    EncodableList list;
    for (const auto& m : monitors) {
      EncodableMap entry;
      entry[EncodableValue("index")] = EncodableValue(m.index);
      entry[EncodableValue("left")] = EncodableValue(m.left);
      entry[EncodableValue("top")] = EncodableValue(m.top);
      entry[EncodableValue("width")] = EncodableValue(m.width);
      entry[EncodableValue("height")] = EncodableValue(m.height);
      entry[EncodableValue("primary")] = EncodableValue(m.is_primary);
      entry[EncodableValue("name")] = EncodableValue(m.name);
      list.push_back(EncodableValue(entry));
    }
    // Virtual desktop entry for "all monitors".
    EncodableMap all;
    all[EncodableValue("index")] = EncodableValue(-1);
    all[EncodableValue("left")] =
        EncodableValue(GetSystemMetrics(SM_XVIRTUALSCREEN));
    all[EncodableValue("top")] =
        EncodableValue(GetSystemMetrics(SM_YVIRTUALSCREEN));
    all[EncodableValue("width")] =
        EncodableValue(GetSystemMetrics(SM_CXVIRTUALSCREEN));
    all[EncodableValue("height")] =
        EncodableValue(GetSystemMetrics(SM_CYVIRTUALSCREEN));
    all[EncodableValue("primary")] = EncodableValue(false);
    all[EncodableValue("name")] = EncodableValue(std::string("All displays"));
    list.push_back(EncodableValue(all));
    result->Success(EncodableValue(list));
    return;
  }
  if (method == "captureScreenJpeg") {
    const auto* args = std::get_if<EncodableMap>(call.arguments());
    const int quality = ReadIntArg(args, "quality", 50);
    const int max_width = ReadIntArg(args, "maxWidth", 1280);
    const int monitor_index = ReadIntArg(args, "monitorIndex", 0);
    win7_rd_capture::JpegFrame frame;
    if (!win7_rd_capture::CaptureScreenJpeg(quality, max_width, monitor_index,
                                            &frame)) {
      result->Error("capture_failed", "GDI/JPEG screen capture failed");
      return;
    }
    EncodableMap map;
    map[EncodableValue("jpeg")] = EncodableValue(frame.jpeg);
    map[EncodableValue("width")] = EncodableValue(frame.width);
    map[EncodableValue("height")] = EncodableValue(frame.height);
    result->Success(EncodableValue(map));
    return;
  }
  if (method == "showNotifyBalloon") {
    const auto* args = std::get_if<EncodableMap>(call.arguments());
    const std::string title = ReadStringArg(args, "title");
    const std::string body = ReadStringArg(args, "body");
    const bool ok = ShowNotifyBalloon(title, body);
    result->Success(EncodableValue(ok));
    return;
  }
  result->NotImplemented();
}

}  // namespace

void Setup(flutter::BinaryMessenger* messenger,
           flutter::PluginRegistry* registry) {
  if (!messenger || !registry) {
    return;
  }
  g_registry = registry;
  g_channel = std::make_unique<MethodChannel<EncodableValue>>(
      messenger, "scn/win7_rd",
      &flutter::StandardMethodCodec::GetInstance());
  g_channel->SetMethodCallHandler(
      [](const MethodCall<EncodableValue>& call,
         std::unique_ptr<MethodResult<EncodableValue>> result) {
        HandleMethodCall(call, std::move(result));
      });
  win7_crash_log::Write(L"win7_rd channel ready");
}

void Shutdown() {
  g_channel.reset();
  g_registry = nullptr;
}

}  // namespace win7_rd_channel
