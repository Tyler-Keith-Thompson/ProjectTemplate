// swift-tools-version: 6.3
import PackageDescription

// libFuzzer targets, in their own package so the library never depends on the fuzzer runtime.
// Xcode's toolchain does not ship libFuzzer; `just fuzz` builds these with a swift.org toolchain
// installed by swiftly. See Fuzz/README.md.

func target(_ name: String, _ modules: [String]) -> Target {
    .executableTarget(
        name: name,
        dependencies: ["FuzzSupport"] + modules.map { .product(name: $0, package: "ProjectName") }
    )
}

let package = Package(
    name: "ProjectNameFuzz",
    platforms: [.macOS(.v15)],
    dependencies: [.package(path: "..")],
    targets: [
        // libFuzzer's driver, declared in a C header (it is defined by the runtime -sanitize=fuzzer links).
        .systemLibrary(name: "CLibFuzzer", path: "Sources/CLibFuzzer"),
        .target(name: "FuzzSupport", dependencies: ["CLibFuzzer"]),
        target("FuzzGreetings", ["Greetings"]),
    ]
)
