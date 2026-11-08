"""Embedded Swift for the firmware's chip.

`embedded_swift_module` compiles a module's sources as Embedded Swift for RISC-V, next to the
host `swift_library` that tests run against, so `bazel build //...` fails when a module uses
something Embedded Swift lacks (Foundation, `any` existentials, reflection). scripts/modules.py
writes one for every module in FIRMWARE_MODULES and its dependencies.

`embedded_swift_firmware` gathers those modules for the firmware's ESP-IDF build
(Firmware/CMakeLists.txt): one static archive of their code, their .swiftmodule files in one
directory for the app to import, and the architecture they were compiled for, which the firmware
build checks against the chip's.

Both run swiftc through tools/embedded-swift, which picks the swift.org toolchain the firmware
build uses too.
"""

# The chip's RISC-V architecture and ABI, as ESP-IDF compiles its own C for it: the ESP32-C6 that
# Firmware/sdkconfig.defaults names. Another chip needs its own, which the firmware build prints
# when they differ (ESP32-C3: rv32imc_zicsr_zifencei; ESP32-P4: rv32imafc_zicsr_zifencei and
# ilp32f).
MARCH = "rv32imac_zicsr_zifencei"
MABI = "ilp32"

EmbeddedSwiftInfo = provider(
    doc = "A module compiled as Embedded Swift, with everything it needs to link and import.",
    fields = {
        "objects": "depset of the object files of the module and its dependencies",
        "swiftmodules": "depset of the .swiftmodule files of the module and its dependencies",
    },
)

# What tools/embedded-swift's swiftc gets for every module. ESP-IDF's idf_swift component compiles
# the app with the same flags (its idf_component_register_swift), and objects linked together must
# agree. Code is never position-independent on the chip.
_FLAGS = [
    "-target",
    "riscv32-none-none-eabi",
    "-Xcc",
    "-march=" + MARCH,
    "-Xcc",
    "-mabi=" + MABI,
    "-Xcc",
    "-fno-pic",
    "-Xcc",
    "-fno-pie",
    "-enable-experimental-feature",
    "Embedded",
    "-wmo",
    "-parse-as-library",
    "-Osize",
    "-Xfrontend",
    "-function-sections",
    # As tools/swift_rules.bzl holds the host build: Swift 6 mode, first-party warnings as errors.
    "-swift-version",
    "6",
    "-warnings-as-errors",
]

def _directory(file):
    return file.dirname

def _embedded_swift_module_impl(ctx):
    module = ctx.attr.module_name
    swiftmodule = ctx.actions.declare_file("{}/{}.swiftmodule".format(ctx.label.name, module))
    obj = ctx.actions.declare_file("{}/{}.o".format(ctx.label.name, module))
    dependencies = [dependency[EmbeddedSwiftInfo] for dependency in ctx.attr.deps]
    imported = depset(transitive = [dependency.swiftmodules for dependency in dependencies])

    arguments = ctx.actions.args()
    arguments.add("swiftc")
    arguments.add_all(_FLAGS)
    arguments.add("-package-name", ctx.attr.package_name)
    arguments.add("-module-name", module)
    # Each dependency's .swiftmodule sits in a directory of its own.
    arguments.add_all(imported, map_each = _directory, before_each = "-I", uniquify = True)
    arguments.add("-emit-module-path", swiftmodule)
    arguments.add("-c")
    arguments.add("-o", obj)
    arguments.add_all(ctx.files.srcs)

    ctx.actions.run(
        executable = ctx.executable._embedded_swift,
        arguments = [arguments],
        inputs = depset(ctx.files.srcs, transitive = [imported]),
        outputs = [swiftmodule, obj],
        mnemonic = "EmbeddedSwiftCompile",
        progress_message = "Compiling %{label} as Embedded Swift",
        # The toolchain lives outside the workspace, found through PATH and the home directory.
        use_default_shell_env = True,
    )
    return [
        DefaultInfo(files = depset([swiftmodule, obj])),
        EmbeddedSwiftInfo(
            objects = depset([obj], transitive = [dependency.objects for dependency in dependencies]),
            swiftmodules = depset([swiftmodule], transitive = [imported]),
        ),
    ]

embedded_swift_module = rule(
    implementation = _embedded_swift_module_impl,
    doc = "A module's sources compiled as Embedded Swift for the chip: one object file and its .swiftmodule.",
    attrs = {
        "srcs": attr.label_list(allow_files = [".swift"], mandatory = True),
        "module_name": attr.string(mandatory = True),
        "deps": attr.label_list(providers = [EmbeddedSwiftInfo]),
        # As tools/swift_rules.bzl names the package, so `package` access works across modules.
        "package_name": attr.string(mandatory = True),
        "_embedded_swift": attr.label(
            default = "//tools:embedded-swift",
            executable = True,
            cfg = "exec",
            allow_single_file = True,
        ),
    },
)

def _embedded_swift_firmware_impl(ctx):
    modules = [module[EmbeddedSwiftInfo] for module in ctx.attr.modules]
    objects = depset(transitive = [module.objects for module in modules])
    swiftmodules = depset(transitive = [module.swiftmodules for module in modules])

    archive = ctx.actions.declare_file("{}/lib{}.a".format(ctx.label.name, ctx.label.name))
    arguments = ctx.actions.args()
    arguments.add("llvm-ar")
    # Deterministic (no timestamps), so an unchanged archive keeps its cache key.
    arguments.add("crsD")
    arguments.add(archive)
    arguments.add_all(objects)
    ctx.actions.run(
        executable = ctx.executable._embedded_swift,
        arguments = [arguments],
        inputs = objects,
        outputs = [archive],
        mnemonic = "EmbeddedSwiftArchive",
        progress_message = "Archiving the firmware's Embedded Swift modules",
        use_default_shell_env = True,
    )

    # One directory for the app to import from (`-I`).
    imports = []
    for swiftmodule in swiftmodules.to_list():
        link = ctx.actions.declare_file("{}/{}".format(ctx.label.name, swiftmodule.basename))
        ctx.actions.symlink(output = link, target_file = swiftmodule)
        imports.append(link)

    architecture = ctx.actions.declare_file("{}/architecture.cmake".format(ctx.label.name))
    ctx.actions.write(
        output = architecture,
        content = "\n".join([
            "# Written by //{}:{} (tools/embedded.bzl): what the modules were compiled for.".format(ctx.label.package, ctx.label.name),
            'set(EMBEDDED_SWIFT_MARCH "{}")'.format(MARCH),
            'set(EMBEDDED_SWIFT_MABI "{}")'.format(MABI),
            "",
        ]),
    )
    return [DefaultInfo(files = depset([archive, architecture] + imports))]

embedded_swift_firmware = rule(
    implementation = _embedded_swift_firmware_impl,
    doc = "The modules the firmware imports, for its ESP-IDF build: lib<name>.a, the .swiftmodule files and architecture.cmake, in <name>/.",
    attrs = {
        "modules": attr.label_list(providers = [EmbeddedSwiftInfo], mandatory = True),
        "_embedded_swift": attr.label(
            default = "//tools:embedded-swift",
            executable = True,
            cfg = "exec",
            allow_single_file = True,
        ),
    },
)
