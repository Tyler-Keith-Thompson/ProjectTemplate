# The app: the Swift in this directory, compiled by ESP-IDF's idf_swift component against the
# modules Bazel compiled (EMBEDDED_SWIFT_MODULES, from ../CMakeLists.txt). Every ESP-IDF component
# the Swift calls into goes in PRIV_REQUIRES, and its header in BridgingHeader.h.
#
# ESP-IDF first reads this file as a script for the requirements alone, which stops at
# idf_component_register; everything after it runs only in the real configure.
idf_component_register(
    # No C sources; ESP-IDF still wants a component to hang the Swift on.
    SRCS /dev/null
    PRIV_INCLUDE_DIRS "."
    PRIV_REQUIRES idf_swift freertos
    # Swift reaches some C globals through the GOT, which ESP-IDF's linker script would discard.
    LDFRAGMENTS swift.lf
)
# Bazel brings the modules up to date before the app compiles, and the build stops unless they were
# compiled for this chip's architecture (tools/embedded.bzl names it).
extract_riscv_flags(chip_flags)
set(modules_archive "${EMBEDDED_SWIFT_MODULES}/libModules.a")
add_custom_target(embedded_swift_modules
    COMMAND "${BAZEL}" build //Firmware:Modules
    COMMAND "${CMAKE_COMMAND}" "-DMODULES=${EMBEDDED_SWIFT_MODULES}" "-DCHIP_FLAGS=${chip_flags}"
        -P "${CMAKE_CURRENT_LIST_DIR}/check-architecture.cmake"
    WORKING_DIRECTORY "${PROJECT_ROOT}"
    BYPRODUCTS "${modules_archive}"
    COMMENT "Building the Embedded Swift modules with Bazel"
    USES_TERMINAL
)

# Embedded Swift inlines across modules, so the app recompiles whenever they change. CMake doesn't
# track a Swift target's imports, so an empty source, touched whenever the modules' archive
# changes, stands in for them.
set(modules_changed "${CMAKE_CURRENT_BINARY_DIR}/EmbeddedSwiftModules.swift")
add_custom_command(
    OUTPUT "${modules_changed}"
    COMMAND "${CMAKE_COMMAND}" -E touch "${modules_changed}"
    DEPENDS "${modules_archive}" embedded_swift_modules
)

file(GLOB APP_SOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_LIST_DIR}/*.swift")
idf_component_register_swift(
    ${COMPONENT_LIB}
    BRIDGING_HEADER "${CMAKE_CURRENT_LIST_DIR}/BridgingHeader.h"
    SRCS ${APP_SOURCES} "${modules_changed}"
)

# As the modules are compiled (tools/embedded.bzl): Swift 6 mode, warnings as errors, one package.
target_compile_options(${COMPONENT_LIB} PRIVATE
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-I ${EMBEDDED_SWIFT_MODULES} -swift-version 6 -warnings-as-errors -package-name projectname>"
)
add_prebuilt_library(embedded_swift_archive "${modules_archive}")
target_link_libraries(${COMPONENT_LIB} PRIVATE
    embedded_swift_archive
    # Unicode tables for String comparison and hashing; only the parts the code uses are linked.
    "${EMBEDDED_SWIFT_TOOLCHAIN}/lib/swift/embedded/riscv32-none-none-eabi/libswiftUnicodeDataTables.a"
)
