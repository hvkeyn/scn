#pragma once

namespace win7_env {

// Win7-only tweaks (ANGLE platform, etc.). Safe no-op on newer Windows.
void Apply();

// True on Windows 7 (RtlGetVersion, not affected by version lie).
bool IsWindows7();

}  // namespace win7_env
