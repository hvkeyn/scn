// Best-effort shim for Windows 7.
//
// flutter_windows.dll imports PathCch* from api-ms-win-core-path-l1-1-0.dll,
// which is not present on Windows 7. Place this DLL next to scn.exe.

#include <windows.h>
#include <shlwapi.h>

#ifndef PATHCCH_ALLOW_LONG_PATHS
#define PATHCCH_ALLOW_LONG_PATHS 0x01
#endif

namespace {

bool CopyIfFits(PWSTR dest, size_t cch_dest, PCWSTR src, HRESULT* out) {
  if (!dest || cch_dest == 0 || !src || !out) {
    *out = E_INVALIDARG;
    return false;
  }
  const size_t len = wcslen(src);
  if (len >= cch_dest) {
    dest[0] = L'\0';
    *out = HRESULT_FROM_WIN32(ERROR_INSUFFICIENT_BUFFER);
    return false;
  }
  wcscpy_s(dest, cch_dest, src);
  *out = S_OK;
  return true;
}

}  // namespace

extern "C" {

__declspec(dllexport) HRESULT WINAPI PathCchCombineEx(PWSTR psz_dest,
                                                      size_t cch_dest,
                                                      PCWSTR psz_dir,
                                                      PCWSTR psz_src,
                                                      unsigned long dw_flags) {
  (void)dw_flags;

  if (!psz_dest || cch_dest == 0) {
    return E_INVALIDARG;
  }
  psz_dest[0] = L'\0';

  if (!psz_dir && !psz_src) {
    return E_INVALIDARG;
  }

  HRESULT hr = S_OK;
  if (!psz_dir || !*psz_dir) {
    return CopyIfFits(psz_dest, cch_dest, psz_src, &hr) ? hr : hr;
  }
  if (!psz_src || !*psz_src) {
    return CopyIfFits(psz_dest, cch_dest, psz_dir, &hr) ? hr : hr;
  }

  if (PathIsRelativeW(psz_src) == FALSE) {
    return CopyIfFits(psz_dest, cch_dest, psz_src, &hr) ? hr : hr;
  }

  wchar_t combined[MAX_PATH] = {};
  if (!PathCombineW(combined, psz_dir, psz_src)) {
    return E_FAIL;
  }
  return CopyIfFits(psz_dest, cch_dest, combined, &hr) ? hr : hr;
}

__declspec(dllexport) HRESULT WINAPI PathCchRemoveFileSpec(PWSTR psz_path,
                                                           size_t cch_path) {
  if (!psz_path || cch_path == 0) {
    return E_INVALIDARG;
  }
  if (wcslen(psz_path) >= cch_path) {
    return E_INVALIDARG;
  }
  return PathRemoveFileSpecW(psz_path) ? S_OK : S_FALSE;
}

}  // extern "C"
