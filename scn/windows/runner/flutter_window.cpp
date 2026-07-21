#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "win7_crash_log.h"
#include "win7_env.h"
#include "win7_flutter_diag.h"
#include "win7_rd_channel.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  win7_crash_log::Write(L"FlutterWindow::OnCreate start");
  if (!Win32Window::OnCreate()) {
    win7_crash_log::Write(L"Win32Window::OnCreate failed");
    return false;
  }

  RECT frame = GetClientArea();
  if (win7_env::IsWindows7()) {
    win7_flutter_diag::LogDataBundle();
    // Skip probe create/destroy: a second engine right before the real
    // FlutterViewController has been linked to post-show crashes on Win7.
  }
  win7_crash_log::Write(L"creating FlutterViewController");

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  win7_crash_log::Write(L"FlutterViewController created");
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  win7_crash_log::Write(L"RegisterPlugins start");
  RegisterPlugins(flutter_controller_->engine());
  win7_crash_log::Write(L"RegisterPlugins done");

  // Always register: GDI JPEG capture is used for Win7 RD and for
  // SCN_RD_FRAMES=1 smoke on Win10+. WebRTC enable* methods no-op off Win7.
  win7_rd_channel::Setup(flutter_controller_->engine()->messenger(),
                         flutter_controller_->engine());

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  if (win7_env::IsWindows7()) {
    // Show before the first frame: deferred Show + ForceRedraw can crash the
    // Win7 software renderer when the window becomes visible.
    win7_crash_log::Write(L"Win7 early Show start");
    Show();
    win7_crash_log::Write(L"Win7 early Show done");
    flutter_controller_->engine()->SetNextFrameCallback([this]() {
      win7_crash_log::Write(L"first frame callback");
      win7_crash_log::Write(L"Win7 UI ready");
    });
  } else {
    flutter_controller_->engine()->SetNextFrameCallback([&]() {
      this->Show();
    });
    flutter_controller_->ForceRedraw();
  }

  return true;
}

void FlutterWindow::OnDestroy() {
  win7_rd_channel::Shutdown();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (win7_env::IsWindows7()) {
    switch (message) {
      case WM_SHOWWINDOW:
        win7_crash_log::Write(L"WM_SHOWWINDOW");
        break;
      case WM_PAINT:
        win7_crash_log::Write(L"WM_PAINT");
        break;
      case WM_SIZE:
        win7_crash_log::Write(L"WM_SIZE");
        break;
      default:
        break;
    }
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
