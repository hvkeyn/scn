#ifndef RUNNER_WIN7_MESH_CHANNEL_H_
#define RUNNER_WIN7_MESH_CHANNEL_H_

#include <windows.h>

namespace win7_mesh_channel {

constexpr UINT kArmMeshTimerMsg = WM_APP + 100;

// Post to the main window thread; SetNextFrameCallback may run off-thread.
void RequestArmMeshStartTimer(HWND hwnd);

// Handle kArmMeshTimerMsg on the window thread (main message loop).
void HandleArmMeshStartRequest();

// Called every 2s from the Win7 heartbeat WM_TIMER handler.
void OnHeartbeat();

}  // namespace win7_mesh_channel

#endif  // RUNNER_WIN7_MESH_CHANNEL_H_
