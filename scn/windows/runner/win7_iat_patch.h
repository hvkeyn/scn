#pragma once

#include <windows.h>

namespace win7_iat {

// Load a DLL from the exe directory with DONT_RESOLVE + manual IAT fixups.
HMODULE LoadModuleWithWin7Imports(const wchar_t* module_name);

// Redirect Win8+ imports to local Win7 shims. Returns false on failure.
bool PatchProcessImports();

}  // namespace win7_iat
