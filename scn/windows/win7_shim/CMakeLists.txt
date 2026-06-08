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

install(TARGETS shcore_scaling_shim scn_ws2
  RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)
