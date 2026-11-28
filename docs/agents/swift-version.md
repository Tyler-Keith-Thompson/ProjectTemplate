# Raising the Swift floor

Raise the Swift floor (a dependency's manifest needs a newer Swift): set `SWIFT` (every
manifest's tools version, CI's and the Docker image's Swift, the minimum the docs state) and
`SWIFT_TOOLCHAIN` (the swift.org release swiftly installs where Xcode's toolchain falls short)
in `scripts/modules.py`, then `just modules`. It writes them into the generated manifests and
replaces the previous ones in every other file that names them (`SWIFT_SITES`), from the record
in `tools/swift_version.bzl`. Never edit a version in those files by hand. `just template-update`
keeps the project's versions, and says when the template's have passed them.
The fuzz targets build with `SWIFT_TOOLCHAIN`. <!-- fuzz:line -->
`just wasi-test` builds with `SWIFT_TOOLCHAIN` and its WebAssembly SDK. <!-- wasm:line -->
The explorer builds with `SWIFT_TOOLCHAIN` and its WebAssembly SDK. <!-- explore:line -->
The firmware builds with `SWIFT_TOOLCHAIN`'s Embedded Swift. <!-- embedded:line -->
CI needs a `swift-bazel` image of the new version, published from the project template's <!-- ci:line -->
`ci-image/build.sh`; with the explorer, `just modules` asks for docc.yml's `WASM_SDK_SHA256`. <!-- ci:line --><!-- explore:line -->
`ci-image/build.sh`. <!-- ci:line --><!-- !explore:line -->
<!-- ci:begin -->

## The CI image

CI's Bazel jobs run in `ghcr.io/tyler-keith-thompson/swift-bazel:<swift>-<bazel>`, Swift with the
Bazel in `.bazelversion` already in it, built by the project template's `ci-image/build.sh`.
Changing `.bazelversion` or the workflows' Swift version means a new tag from there. The package
is private; a repository pulls it once added under its Manage Actions access.
<!-- ci:end -->
