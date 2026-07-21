#ifndef RUNNER_WIN7_RD_CAPTURE_H_
#define RUNNER_WIN7_RD_CAPTURE_H_

#include <cstdint>
#include <string>
#include <vector>

namespace win7_rd_capture {

struct JpegFrame {
  std::vector<uint8_t> jpeg;
  int width = 0;
  int height = 0;
};

struct MonitorInfo {
  int index = 0;
  int left = 0;
  int top = 0;
  int width = 0;
  int height = 0;
  bool is_primary = false;
  std::string name;
};

// Enumerate physical monitors (sorted by left, then top).
std::vector<MonitorInfo> ListMonitors();

// GDI BitBlt (+ CAPTUREBLT) → optional downscale → JPEG (GDI+).
// quality: 1..100, max_width: 0 = native width.
// monitor_index: >=0 physical monitor, -1 = full virtual desktop.
bool CaptureScreenJpeg(int quality, int max_width, int monitor_index,
                       JpegFrame* out);

}  // namespace win7_rd_capture

#endif  // RUNNER_WIN7_RD_CAPTURE_H_
