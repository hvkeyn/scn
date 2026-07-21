#pragma once

namespace win7_mesh_signal {

// Create signal files when the Flutter engine reports its first frame.
void SignalNativeFirstFrame();

// Create scn_win7_start_mesh next to scn.exe when mesh should start.
void WriteStartMeshSignal();

// Remove stale signals from a previous run.
void ClearSignalFile();

}  // namespace win7_mesh_signal
