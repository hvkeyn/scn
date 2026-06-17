#ifndef RUNNER_RD_INPUT_SERVICE_H_
#define RUNNER_RD_INPUT_SERVICE_H_

// SCN Remote Desktop — privileged input service.
//
// To inject mouse/keyboard into UAC (consent.exe) and other System-integrity
// windows, input must originate from a process running as LocalSystem inside
// the interactive user session. This module implements that helper:
//
//   scn.exe --rd-service     Runs as a Windows service (LocalSystem, session 0).
//                            Spawns the worker in the active console session.
//   scn.exe --rd-worker      Runs as SYSTEM inside the user session. Hosts a
//                            named pipe and replays input via SendInput after
//                            switching to the current input desktop (handles the
//                            secure/UAC desktop).
//   scn.exe --rd-install     Installs + starts the service (run elevated).
//   scn.exe --rd-uninstall   Stops + removes the service (run elevated).
//
// The main Flutter process writes input commands to the pipe; see the Dart
// side service_input_bridge.dart.

namespace rd_service {

// If the current process command line is one of the RD service/worker/install
// commands, handles it fully and sets *exit_code. Returns true in that case so
// wWinMain returns immediately without starting Flutter. Returns false for a
// normal app launch.
bool HandleCommandLine(int* exit_code);

}  // namespace rd_service

#endif  // RUNNER_RD_INPUT_SERVICE_H_
