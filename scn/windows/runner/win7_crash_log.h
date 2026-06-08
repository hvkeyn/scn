#ifndef RUNNER_WIN7_CRASH_LOG_H_
#define RUNNER_WIN7_CRASH_LOG_H_

namespace win7_crash_log {

void Install();
void Write(const wchar_t* message);

}  // namespace win7_crash_log

#endif  // RUNNER_WIN7_CRASH_LOG_H_
