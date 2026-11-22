// swift-tools-version: 6.3
import PackageDescription

// The example apps, in their own package so the published library never depends on what they use.
// It depends on the library by path. Hand-written, unlike the root manifest: scripts/modules.py
// doesn't generate it. `just examples-test` tests it; see Examples/README.md.

// Bazel's files sit beside the sources the Apple apps build (Examples/Apps/ExampleApp).
let bazelFiles = ["BUILD.bazel"]

let package = Package(
    name: "ProjectNameExamples",
    platforms: [.macOS(.v15), .iOS(.v18), .watchOS(.v11), .visionOS(.v2)],
    dependencies: [
        // Named, so the identity does not depend on the checkout directory's name.
        .package(name: "ProjectName", path: ".."),
    ],
    targets: [
        .target(
            name: "ExampleViews",
            dependencies: [.product(name: "Greetings", package: "ProjectName")],
            exclude: bazelFiles
        ),
        .testTarget(
            name: "ExampleViewsTests",
            dependencies: ["ExampleViews", .product(name: "Greetings", package: "ProjectName")]
        ),
    ]
)
