# The firmware: an ESP-IDF project whose app is Embedded Swift (main/). Bazel compiles the modules
# the app imports (//Firmware:Modules, from FIRMWARE_MODULES in scripts/modules.py); ESP-IDF
# compiles main/ against them and links the image. `just firmware` builds it.
cmake_minimum_required(VERSION 3.29)

get_filename_component(PROJECT_ROOT "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)

# One compiler for the modules and the app: tools/embedded-swift's swift.org toolchain, which has
# Embedded Swift for RISC-V. ESP-IDF's idf_swift component uses CMAKE_Swift_COMPILER when set.
execute_process(
    COMMAND "${PROJECT_ROOT}/tools/embedded-swift" toolchain
    OUTPUT_VARIABLE EMBEDDED_SWIFT_TOOLCHAIN
    OUTPUT_STRIP_TRAILING_WHITESPACE
    COMMAND_ERROR_IS_FATAL ANY
)
set(CMAKE_Swift_COMPILER "${EMBEDDED_SWIFT_TOOLCHAIN}/bin/swiftc")

# Where Bazel puts the modules (//Firmware:Modules); main/ has Bazel build them before every compile,
# which does nothing unless a module changed.
find_program(BAZEL NAMES bazel bazelisk REQUIRED)
execute_process(
    COMMAND "${BAZEL}" info bazel-bin
    WORKING_DIRECTORY "${PROJECT_ROOT}"
    OUTPUT_VARIABLE BAZEL_BIN
    OUTPUT_STRIP_TRAILING_WHITESPACE
    COMMAND_ERROR_IS_FATAL ANY
)
set(EMBEDDED_SWIFT_MODULES "${BAZEL_BIN}/Firmware/Modules")

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
# Builds only the components main/ requires, not all of ESP-IDF.
idf_build_set_property(MINIMAL_BUILD ON)
project(projectname)
