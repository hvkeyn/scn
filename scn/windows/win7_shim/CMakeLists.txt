cmake_minimum_required(VERSION 3.14)
project(win7_shim LANGUAGES CXX)

add_library(shcore_scaling_shim SHARED
  shcore_scaling_shim.cpp
  shcore_scaling_shim.def
)

# Exact DLL name expected by the Windows loader / Flutter engine.
set_target_properties(shcore_scaling_shim PROPERTIES
  OUTPUT_NAME "api-ms-win-shcore-scaling-l1-1-1"
  PREFIX ""
)

target_compile_definitions(shcore_scaling_shim PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)

install(TARGETS shcore_scaling_shim
  RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)
