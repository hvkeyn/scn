// Win7 shim: WS2_32.dll on Windows 7 has no GetHostNameW (added in Windows 8).
// flutter_windows.dll imports GetHostNameW; the import is redirected to this DLL
// at build time (see patch_flutter_win7.py).

#include <windows.h>
#include <winsock2.h>

extern "C" {

__declspec(dllexport) int WINAPI ScnGetHostNameW(PWSTR name, int namelen) {
  if (!name || namelen <= 0) {
    WSASetLastError(WSAEINVAL);
    return SOCKET_ERROR;
  }

  char ansi[256] = {};
  if (gethostname(ansi, static_cast<int>(sizeof(ansi) - 1)) != 0) {
    return SOCKET_ERROR;
  }

  if (MultiByteToWideChar(CP_ACP, MB_PRECOMPOSED, ansi, -1, name, namelen) == 0) {
    WSASetLastError(WSAEFAULT);
    return SOCKET_ERROR;
  }
  return 0;
}

}  // extern "C"
