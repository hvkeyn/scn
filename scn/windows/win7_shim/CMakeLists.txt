cmake_minimum_required(VERSION 3.14)
# Do not call project() here: nested project() resets CMAKE_INSTALL_PREFIX
# to "C:/Program Files/..." and INSTALL copies shims to the wrong folder.

# --- helpers --------------------------------------------------------------

set(SCN_FLUTTER_DLL "${CMAKE_SOURCE_DIR}/flutter/ephemeral/flutter_windows.dll")
find_program(SCN_PYTHON3 NAMES python3 python)

# Generate a forwarder .def that re-exports every symbol the target PE imports
# from <system_dll>, forwarding to the real system DLL except for the symbols
# listed in OVERRIDES (which point at local Scn* implementations). This makes
# the shim a drop-in proxy so patch_flutter_win7.py can safely RENAME the
# import descriptor (system_dll -> shim) without breaking load-time import
# resolution.
function(scn_gen_proxy_def TARGET_NAME SYSTEM_DLL SHIM_LIBNAME OUTPUT_DEF)
  set(cmd_args "")
  set(mode "override")
  foreach(arg IN LISTS ARGN)
    if(arg STREQUAL "EXTRA")
      set(mode "extra")
      continue()
    endif()
    if(mode STREQUAL "extra")
      list(APPEND cmd_args "--extra" "${arg}")
    else()
      list(APPEND cmd_args "--override" "${arg}")
    endif()
  endforeach()

  if(SCN_PYTHON3 AND EXISTS "${SCN_FLUTTER_DLL}")
    add_custom_command(
      OUTPUT "${OUTPUT_DEF}"
      COMMAND "${SCN_PYTHON3}"
              "${CMAKE_CURRENT_SOURCE_DIR}/gen_proxy_shim_def.py"
              "${SCN_FLUTTER_DLL}"
              "${SYSTEM_DLL}"
              "${SHIM_LIBNAME}"
              ${cmd_args}
              "-o" "${OUTPUT_DEF}"
      DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/gen_proxy_shim_def.py"
              "${SCN_FLUTTER_DLL}"
      COMMENT "Generating ${SHIM_LIBNAME} proxy .def from flutter ${SYSTEM_DLL} imports"
      VERBATIM)
    add_custom_target(${TARGET_NAME} DEPENDS "${OUTPUT_DEF}")
  else()
    # Fallback: keep the hand-written .def checked into the tree.
    message(STATUS "python/flutter_windows.dll missing; ${SHIM_LIBNAME} uses checked-in .def")
  endif()
endfunction()

# --- api-ms-win-* shims (statically linked stubs) -------------------------

add_library(shcore_scaling_shim SHARED
  shcore_scaling_shim.cpp
  shcore_scaling_shim.def
)

set_target_properties(shcore_scaling_shim PROPERTIES
  OUTPUT_NAME "api-ms-win-shcore-scaling-l1-1-1"
  PREFIX ""
)

target_compile_definitions(shcore_scaling_shim PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)

add_library(core_path_shim SHARED
  core_path_shim.cpp
  core_path_shim.def
)

set_target_properties(core_path_shim PROPERTIES
  OUTPUT_NAME "api-ms-win-core-path-l1-1-0"
  PREFIX ""
)

target_compile_definitions(core_path_shim PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_link_libraries(core_path_shim PRIVATE shlwapi)

# --- scn_ws2: full WS2 proxy + GetHostNameW override ----------------------

if(SCN_PYTHON3 AND EXISTS "${SCN_FLUTTER_DLL}")
  add_custom_command(
    OUTPUT "${CMAKE_CURRENT_SOURCE_DIR}/ws2_hostname_shim.def"
    COMMAND "${SCN_PYTHON3}"
            "${CMAKE_CURRENT_SOURCE_DIR}/gen_ws2_shim_def.py"
            "${SCN_FLUTTER_DLL}"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/gen_ws2_shim_def.py"
            "${SCN_FLUTTER_DLL}"
    COMMENT "Generating ws2_hostname_shim.def from flutter WS2 imports"
    VERBATIM)
  add_custom_target(scn_ws2_def
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/ws2_hostname_shim.def")
endif()

add_library(scn_ws2 SHARED
  ws2_hostname_shim.cpp
  ws2_hostname_shim.def
)

if(TARGET scn_ws2_def)
  add_dependencies(scn_ws2 scn_ws2_def)
endif()

set_target_properties(scn_ws2 PROPERTIES
  OUTPUT_NAME "scn_ws2"
  PREFIX ""
)

target_compile_definitions(scn_ws2 PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_link_libraries(scn_ws2 PRIVATE ws2_32)

# --- scn_ntdll: full ntdll proxy + Win8 unwind/condition overrides --------
# The .def is GENERATED from flutter_windows.dll's ntdll imports so that every
# symbol (RtlAllocateHeap, NtQueryPerformanceCounter, ...) forwards to the
# real ntdll, while the 4 Win8+ symbols are replaced by local Scn* shims.
# ntdll.dll is renamed to scn_ntdll.dll at build time by patch_flutter_win7.py.

set(SCN_NTDLL_DEF "${CMAKE_CURRENT_SOURCE_DIR}/ntdll_shim.def")
scn_gen_proxy_def(scn_ntdll_def_target "ntdll.dll" "scn_ntdll" "${SCN_NTDLL_DEF}"
  "RtlAddGrowableFunctionTable=ScnRtlAddGrowableFunctionTable"
  "RtlDeleteGrowableFunctionTable=ScnRtlDeleteGrowableFunctionTable"
  "VerSetConditionMask=ScnVerSetConditionMask"
  EXTRA
  "RtlGrowFunctionTable=ScnRtlGrowFunctionTable"
  "ScnWin7TlsCallback"
  "ScnHookedGetProcAddress"
  "ScnPatchFlutterGetProcAddress"
)

add_library(scn_ntdll SHARED
  ntdll_shim.cpp
  gpa_redirect.cpp
  ntdll_shim.def
)

if(TARGET scn_ntdll_def_target)
  add_dependencies(scn_ntdll scn_ntdll_def_target)
endif()

set_target_properties(scn_ntdll PROPERTIES
  OUTPUT_NAME "scn_ntdll"
  PREFIX ""
)

target_compile_definitions(scn_ntdll PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)

# --- scn_kernel32: full kernel32 proxy + Win8 locale/file-info overrides ---
# kernel32.dll is renamed to scn_kernel32.dll at build time by
# patch_flutter_win7.py.

set(SCN_KERNEL32_DEF "${CMAKE_CURRENT_SOURCE_DIR}/kernel32_shim.def")
scn_gen_proxy_def(scn_kernel32_def_target "kernel32.dll" "scn_kernel32" "${SCN_KERNEL32_DEF}"
  "CompareStringEx=ScnCompareStringEx"
  "LCMapStringEx=ScnLCMapStringEx"
  "GetFileInformationByHandleEx=ScnGetFileInformationByHandleEx"
)

add_library(scn_kernel32 SHARED
  kernel32_shim.cpp
  kernel32_shim.def
)

if(TARGET scn_kernel32_def_target)
  add_dependencies(scn_kernel32 scn_kernel32_def_target)
endif()

set_target_properties(scn_kernel32 PROPERTIES
  OUTPUT_NAME "scn_kernel32"
  PREFIX ""
)

target_compile_definitions(scn_kernel32 PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)

# --- GPU block shims (dxgi/d3d11) -----------------------------------------

add_library(scn_dxgi SHARED
  dxgi_shim.cpp
  dxgi_shim.def
)

set_target_properties(scn_dxgi PROPERTIES
  OUTPUT_NAME "scn_dxgi"
  PREFIX ""
)

target_compile_definitions(scn_dxgi PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_link_libraries(scn_dxgi PRIVATE dxgi)

add_library(scn_d3d11 SHARED
  d3d11_shim.cpp
  d3d11_shim.def
)

set_target_properties(scn_d3d11 PROPERTIES
  OUTPUT_NAME "scn_d3d11"
  PREFIX ""
)

target_compile_definitions(scn_d3d11 PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_link_libraries(scn_d3d11 PRIVATE d3d11)

install(TARGETS shcore_scaling_shim core_path_shim scn_ws2 scn_ntdll scn_kernel32 scn_dxgi scn_d3d11
  RUNTIME DESTINATION "$<TARGET_FILE_DIR:scn>"
  COMPONENT Runtime)
