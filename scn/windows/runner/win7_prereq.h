#ifndef RUNNER_WIN7_PREREQ_H_
#define RUNNER_WIN7_PREREQ_H_

namespace win7_prereq {

// True on Windows 7 / Server 2008 R2 (6.1).
bool IsWindows7();

// Checks VC++ 2015-2022 and UCRT (KB2999226). On missing components offers
// automatic download/install or opening official download pages.
// Returns false if the user chose to exit.
bool EnsurePrerequisites();

}  // namespace win7_prereq

#endif  // RUNNER_WIN7_PREREQ_H_
