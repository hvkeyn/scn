#include "win7_rd_capture.h"

#include <objidl.h>
#include <windows.h>

#include <gdiplus.h>

#include <algorithm>
#include <mutex>
#include <sstream>

#pragma comment(lib, "gdiplus.lib")
#pragma comment(lib, "gdi32.lib")
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "ole32.lib")

namespace win7_rd_capture {
namespace {

std::once_flag g_gdiplus_once;
ULONG_PTR g_gdiplus_token = 0;

void EnsureGdiplus() {
  std::call_once(g_gdiplus_once, []() {
    Gdiplus::GdiplusStartupInput input;
    Gdiplus::GdiplusStartup(&g_gdiplus_token, &input, nullptr);
  });
}

int GetEncoderClsid(const WCHAR* format, CLSID* clsid) {
  UINT num = 0;
  UINT size = 0;
  Gdiplus::GetImageEncodersSize(&num, &size);
  if (size == 0) {
    return -1;
  }
  auto* codecs = static_cast<Gdiplus::ImageCodecInfo*>(malloc(size));
  if (!codecs) {
    return -1;
  }
  Gdiplus::GetImageEncoders(num, size, codecs);
  for (UINT i = 0; i < num; ++i) {
    if (wcscmp(codecs[i].MimeType, format) == 0) {
      *clsid = codecs[i].Clsid;
      free(codecs);
      return static_cast<int>(i);
    }
  }
  free(codecs);
  return -1;
}

bool EncodeBitmapToJpeg(HBITMAP hbmp, int quality, std::vector<uint8_t>* out) {
  EnsureGdiplus();
  Gdiplus::Bitmap bitmap(hbmp, nullptr);
  if (bitmap.GetLastStatus() != Gdiplus::Ok) {
    return false;
  }

  CLSID jpeg_clsid;
  if (GetEncoderClsid(L"image/jpeg", &jpeg_clsid) < 0) {
    return false;
  }

  ULONG q = static_cast<ULONG>(std::clamp(quality, 1, 100));
  Gdiplus::EncoderParameters params;
  params.Count = 1;
  params.Parameter[0].Guid = Gdiplus::EncoderQuality;
  params.Parameter[0].Type = Gdiplus::EncoderParameterValueTypeLong;
  params.Parameter[0].NumberOfValues = 1;
  params.Parameter[0].Value = &q;

  IStream* stream = nullptr;
  if (FAILED(CreateStreamOnHGlobal(nullptr, TRUE, &stream)) || !stream) {
    return false;
  }

  const Gdiplus::Status st = bitmap.Save(stream, &jpeg_clsid, &params);
  if (st != Gdiplus::Ok) {
    stream->Release();
    return false;
  }

  HGLOBAL hg = nullptr;
  if (FAILED(GetHGlobalFromStream(stream, &hg)) || !hg) {
    stream->Release();
    return false;
  }
  const SIZE_T size = GlobalSize(hg);
  void* data = GlobalLock(hg);
  if (!data || size == 0) {
    if (data) {
      GlobalUnlock(hg);
    }
    stream->Release();
    return false;
  }
  out->assign(static_cast<uint8_t*>(data),
              static_cast<uint8_t*>(data) + size);
  GlobalUnlock(hg);
  stream->Release();
  return !out->empty();
}

BOOL CALLBACK EnumMonitorsProc(HMONITOR monitor, HDC, LPRECT, LPARAM lparam) {
  auto* list = reinterpret_cast<std::vector<MonitorInfo>*>(lparam);
  MONITORINFOEXW mi = {};
  mi.cbSize = sizeof(mi);
  if (!GetMonitorInfoW(monitor, &mi)) {
    return TRUE;
  }
  MonitorInfo info;
  info.left = mi.rcMonitor.left;
  info.top = mi.rcMonitor.top;
  info.width = mi.rcMonitor.right - mi.rcMonitor.left;
  info.height = mi.rcMonitor.bottom - mi.rcMonitor.top;
  info.is_primary = (mi.dwFlags & MONITORINFOF_PRIMARY) != 0;
  char name_utf8[128] = {};
  WideCharToMultiByte(CP_UTF8, 0, mi.szDevice, -1, name_utf8,
                      static_cast<int>(sizeof(name_utf8) - 1), nullptr, nullptr);
  info.name = name_utf8;
  if (info.width > 0 && info.height > 0) {
    list->push_back(info);
  }
  return TRUE;
}

bool ResolveCaptureRect(int monitor_index, int* src_x, int* src_y, int* src_w,
                        int* src_h) {
  if (monitor_index < 0) {
    *src_x = GetSystemMetrics(SM_XVIRTUALSCREEN);
    *src_y = GetSystemMetrics(SM_YVIRTUALSCREEN);
    *src_w = GetSystemMetrics(SM_CXVIRTUALSCREEN);
    *src_h = GetSystemMetrics(SM_CYVIRTUALSCREEN);
    return *src_w > 0 && *src_h > 0;
  }
  const auto monitors = ListMonitors();
  if (monitor_index >= static_cast<int>(monitors.size())) {
    return false;
  }
  const auto& m = monitors[static_cast<size_t>(monitor_index)];
  *src_x = m.left;
  *src_y = m.top;
  *src_w = m.width;
  *src_h = m.height;
  return *src_w > 0 && *src_h > 0;
}

}  // namespace

std::vector<MonitorInfo> ListMonitors() {
  std::vector<MonitorInfo> list;
  EnumDisplayMonitors(nullptr, nullptr, EnumMonitorsProc,
                      reinterpret_cast<LPARAM>(&list));
  std::stable_sort(list.begin(), list.end(),
                   [](const MonitorInfo& a, const MonitorInfo& b) {
                     if (a.is_primary != b.is_primary) {
                       return a.is_primary && !b.is_primary;
                     }
                     if (a.left != b.left) {
                       return a.left < b.left;
                     }
                     return a.top < b.top;
                   });
  for (size_t i = 0; i < list.size(); ++i) {
    list[i].index = static_cast<int>(i);
    if (list[i].name.empty()) {
      std::ostringstream oss;
      oss << "Monitor " << (i + 1);
      list[i].name = oss.str();
    } else {
      std::ostringstream oss;
      oss << "Monitor " << (i + 1);
      if (list[i].is_primary) {
        oss << " (Primary)";
      }
      oss << " " << list[i].width << "x" << list[i].height;
      list[i].name = oss.str();
    }
  }
  return list;
}

bool CaptureScreenJpeg(int quality, int max_width, int monitor_index,
                       JpegFrame* out) {
  if (!out) {
    return false;
  }
  out->jpeg.clear();
  out->width = 0;
  out->height = 0;

  int src_x = 0;
  int src_y = 0;
  int src_w = 0;
  int src_h = 0;
  if (!ResolveCaptureRect(monitor_index, &src_x, &src_y, &src_w, &src_h)) {
    // Fallback: primary.
    if (!ResolveCaptureRect(0, &src_x, &src_y, &src_w, &src_h)) {
      src_w = GetSystemMetrics(SM_CXSCREEN);
      src_h = GetSystemMetrics(SM_CYSCREEN);
      src_x = 0;
      src_y = 0;
    }
  }
  if (src_w <= 0 || src_h <= 0) {
    return false;
  }

  int dst_w = src_w;
  int dst_h = src_h;
  if (max_width > 0 && src_w > max_width) {
    dst_w = max_width;
    dst_h = static_cast<int>((static_cast<double>(src_h) * max_width) / src_w);
    if (dst_h < 1) {
      dst_h = 1;
    }
  }

  HDC screen_dc = GetDC(nullptr);
  if (!screen_dc) {
    return false;
  }
  HDC mem_dc = CreateCompatibleDC(screen_dc);
  if (!mem_dc) {
    ReleaseDC(nullptr, screen_dc);
    return false;
  }

  BITMAPINFO bmi = {};
  bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bmi.bmiHeader.biWidth = dst_w;
  bmi.bmiHeader.biHeight = -dst_h;  // top-down
  bmi.bmiHeader.biPlanes = 1;
  bmi.bmiHeader.biBitCount = 32;
  bmi.bmiHeader.biCompression = BI_RGB;

  void* bits = nullptr;
  HBITMAP dib =
      CreateDIBSection(mem_dc, &bmi, DIB_RGB_COLORS, &bits, nullptr, 0);
  if (!dib || !bits) {
    if (dib) {
      DeleteObject(dib);
    }
    DeleteDC(mem_dc);
    ReleaseDC(nullptr, screen_dc);
    return false;
  }

  HGDIOBJ old = SelectObject(mem_dc, dib);
  BOOL ok = FALSE;
  if (dst_w == src_w && dst_h == src_h) {
    // 1:1 copy — much faster than StretchBlt for window work.
    ok = BitBlt(mem_dc, 0, 0, dst_w, dst_h, screen_dc, src_x, src_y,
                SRCCOPY | CAPTUREBLT);
  } else {
    // COLORONCOLOR is far cheaper than HALFTONE; use HALFTONE only for
    // high-quality (clarity) downscales.
    SetStretchBltMode(mem_dc, quality >= 80 ? HALFTONE : COLORONCOLOR);
    SetBrushOrgEx(mem_dc, 0, 0, nullptr);
    ok = StretchBlt(mem_dc, 0, 0, dst_w, dst_h, screen_dc, src_x, src_y, src_w,
                    src_h, SRCCOPY | CAPTUREBLT);
  }
  SelectObject(mem_dc, old);

  bool encoded = false;
  if (ok) {
    encoded = EncodeBitmapToJpeg(dib, quality, &out->jpeg);
    if (encoded) {
      out->width = dst_w;
      out->height = dst_h;
    }
  }

  DeleteObject(dib);
  DeleteDC(mem_dc);
  ReleaseDC(nullptr, screen_dc);
  return encoded;
}

}  // namespace win7_rd_capture
