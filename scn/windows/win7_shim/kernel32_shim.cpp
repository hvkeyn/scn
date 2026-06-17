// Win7 shim for kernel32 exports added in Windows 8.

#include <windows.h>

#ifndef FileBasicInfo
#define FileBasicInfo 0
#endif
#ifndef FileStandardInfo
#define FileStandardInfo 1
#endif

typedef enum _SCN_FILE_INFO_BY_HANDLE_CLASS {
  ScnFileBasicInfo = 0,
  ScnFileStandardInfo = 1,
} SCN_FILE_INFO_BY_HANDLE_CLASS;

typedef struct _SCN_FILE_BASIC_INFO {
  LARGE_INTEGER CreationTime;
  LARGE_INTEGER LastAccessTime;
  LARGE_INTEGER LastWriteTime;
  LARGE_INTEGER ChangeTime;
  DWORD FileAttributes;
} SCN_FILE_BASIC_INFO;

typedef struct _SCN_FILE_STANDARD_INFO {
  LARGE_INTEGER AllocationSize;
  LARGE_INTEGER EndOfFile;
  DWORD NumberOfLinks;
  BOOLEAN DeletePending;
  BOOLEAN Directory;
} SCN_FILE_STANDARD_INFO;

extern "C" {

int WINAPI ScnCompareStringEx(LPCWSTR locale_name,
                              DWORD flags,
                              LPCWSTR string1,
                              int count1,
                              LPCWSTR string2,
                              int count2,
                              LPNLSVERSIONINFO /*version_info*/,
                              LPVOID /*reserved*/,
                              LPARAM /*sort_version*/) {
  LCID lcid = LOCALE_USER_DEFAULT;
  if (locale_name && locale_name[0]) {
    const LCID mapped = LocaleNameToLCID(locale_name, 0);
    if (mapped != 0) {
      lcid = mapped;
    }
  }
  return CompareStringW(lcid, flags, string1, count1, string2, count2);
}

int WINAPI ScnLCMapStringEx(LPCWSTR locale_name,
                            DWORD flags,
                            LPCWSTR source,
                            int source_count,
                            LPWSTR dest,
                            int dest_count,
                            LPNLSVERSIONINFO /*version_info*/,
                            LPVOID /*reserved*/,
                            LPARAM /*sort_version*/) {
  LCID lcid = LOCALE_USER_DEFAULT;
  if (locale_name && locale_name[0]) {
    const LCID mapped = LocaleNameToLCID(locale_name, 0);
    if (mapped != 0) {
      lcid = mapped;
    }
  }
  return LCMapStringW(lcid, flags, source, source_count, dest, dest_count);
}

BOOL WINAPI ScnGetFileInformationByHandleEx(HANDLE file,
                                            SCN_FILE_INFO_BY_HANDLE_CLASS info_class,
                                            LPVOID info,
                                            DWORD buffer_size) {
  if (!file || file == INVALID_HANDLE_VALUE || !info) {
    SetLastError(ERROR_INVALID_PARAMETER);
    return FALSE;
  }

  if (info_class == ScnFileBasicInfo) {
    if (buffer_size < sizeof(SCN_FILE_BASIC_INFO)) {
      SetLastError(ERROR_INSUFFICIENT_BUFFER);
      return FALSE;
    }
    FILETIME create_time = {};
    FILETIME access_time = {};
    FILETIME write_time = {};
    if (!GetFileTime(file, &create_time, &access_time, &write_time)) {
      return FALSE;
    }
    auto* out = static_cast<SCN_FILE_BASIC_INFO*>(info);
    BY_HANDLE_FILE_INFORMATION by_handle = {};
    if (GetFileInformationByHandle(file, &by_handle)) {
      out->FileAttributes = by_handle.dwFileAttributes;
      out->CreationTime.LowPart = by_handle.ftCreationTime.dwLowDateTime;
      out->CreationTime.HighPart = by_handle.ftCreationTime.dwHighDateTime;
      out->LastAccessTime.LowPart = by_handle.ftLastAccessTime.dwLowDateTime;
      out->LastAccessTime.HighPart = by_handle.ftLastAccessTime.dwHighDateTime;
      out->LastWriteTime.LowPart = by_handle.ftLastWriteTime.dwLowDateTime;
      out->LastWriteTime.HighPart = by_handle.ftLastWriteTime.dwHighDateTime;
      out->ChangeTime = out->LastWriteTime;
      return TRUE;
    }
    out->CreationTime.LowPart = create_time.dwLowDateTime;
    out->CreationTime.HighPart = create_time.dwHighDateTime;
    out->LastAccessTime.LowPart = access_time.dwLowDateTime;
    out->LastAccessTime.HighPart = access_time.dwHighDateTime;
    out->LastWriteTime.LowPart = write_time.dwLowDateTime;
    out->LastWriteTime.HighPart = write_time.dwHighDateTime;
    out->ChangeTime = out->LastWriteTime;
    out->FileAttributes = FILE_ATTRIBUTE_NORMAL;
    return TRUE;
  }

  if (info_class == ScnFileStandardInfo) {
    if (buffer_size < sizeof(SCN_FILE_STANDARD_INFO)) {
      SetLastError(ERROR_INSUFFICIENT_BUFFER);
      return FALSE;
    }
    LARGE_INTEGER size = {};
    if (!GetFileSizeEx(file, &size)) {
      return FALSE;
    }
    auto* out = static_cast<SCN_FILE_STANDARD_INFO*>(info);
    out->AllocationSize = size;
    out->EndOfFile = size;
    out->NumberOfLinks = 1;
    out->DeletePending = FALSE;
    out->Directory = FALSE;
    BY_HANDLE_FILE_INFORMATION by_handle = {};
    if (GetFileInformationByHandle(file, &by_handle)) {
      out->NumberOfLinks = by_handle.nNumberOfLinks;
      out->Directory =
          (by_handle.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
    }
    return TRUE;
  }

  SetLastError(ERROR_INVALID_PARAMETER);
  return FALSE;
}

}  // extern "C"
