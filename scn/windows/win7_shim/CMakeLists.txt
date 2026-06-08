cmake_minimum_required(VERSION 3.14)
project(win7_shim LANGUAGES CXX)

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

add_library(scn_ws2 SHARED
  ws2_hostname_shim.cpp
  ws2_hostname_shim.def
)

set_target_properties(scn_ws2 PROPERTIES
  OUTPUT_NAME "scn_ws2"
  PREFIX ""
)

target_compile_definitions(scn_ws2 PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_link_libraries(scn_ws2 PRIVATE ws2_32)

add_library(scn_ntdll SHARED
  ntdll_shim.cpp
  ntdll_shim.def
)

set_target_properties(scn_ntdll PROPERTIES
  OUTPUT_NAME "scn_ntdll"
  PREFIX ""
)

target_compile_definitions(scn_ntdll PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)

install(TARGETS shcore_scaling_shim core_path_shim scn_ws2 scn_ntdll
  RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)
