# Fails unless the Swift modules were compiled for the chip's architecture: the modules'
# architecture.cmake (tools/embedded.bzl's MARCH and MABI) against CHIP_FLAGS, which ESP-IDF
# compiles for. Run after every Bazel build of the modules, with
#   cmake -DMODULES=<directory> -DCHIP_FLAGS=<flags> -P check-architecture.cmake
include("${MODULES}/architecture.cmake")
set(module_flags "-Xcc -march=${EMBEDDED_SWIFT_MARCH} -Xcc -mabi=${EMBEDDED_SWIFT_MABI}")
if(NOT CHIP_FLAGS STREQUAL module_flags)
    message(FATAL_ERROR "The Swift modules are compiled with '${module_flags}', but this chip needs "
        "'${CHIP_FLAGS}': set MARCH and MABI in tools/embedded.bzl to match.")
endif()
