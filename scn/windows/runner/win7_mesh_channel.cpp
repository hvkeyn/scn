#include "win7_mesh_channel.h"

#include "win7_crash_log.h"
#include "win7_env.h"
#include "win7_mesh_signal.h"

namespace win7_mesh_channel {
namespace {

constexpr DWORD kMeshDelayMs = 3000;
DWORD g_mesh_start_tick = 0;
bool g_mesh_started = false;

}  // namespace

void RequestArmMeshStartTimer(HWND hwnd) {
  if (!win7_env::IsWindows7() || hwnd == nullptr) {
    return;
  }
  if (!PostMessageW(hwnd, kArmMeshTimerMsg, 0, 0)) {
    win7_crash_log::Write(L"mesh arm PostMessage failed");
    return;
  }
  win7_crash_log::Write(L"mesh arm PostMessage ok");
}

void HandleArmMeshStartRequest() {
  if (!win7_env::IsWindows7() || g_mesh_started) {
    return;
  }
  g_mesh_start_tick = GetTickCount() + kMeshDelayMs;
  win7_crash_log::Write(L"mesh start scheduled 3s (heartbeat)");
}

void OnHeartbeat() {
  if (!win7_env::IsWindows7() || g_mesh_start_tick == 0 || g_mesh_started) {
    return;
  }

  const DWORD now = GetTickCount();
  if ((now - g_mesh_start_tick) >= 0x80000000) {
    return;
  }

  g_mesh_started = true;
  g_mesh_start_tick = 0;
  win7_crash_log::Write(L"mesh start heartbeat fired");
  win7_mesh_signal::WriteStartMeshSignal();
  win7_crash_log::Write(L"mesh start signal file only (no channel invoke)");
}

}  // namespace win7_mesh_channel
