# Explore

Interactive pages that run ProjectName itself in the browser: each builds a small example, runs the
real library on it, and shows what happened, with the code it ran beside it. The interface is
written with [ElementaryUI](https://github.com/elementary-swift/elementary-ui) and compiled with
the library to WebAssembly. The DocC workflow publishes the site next to the documentation, at <!-- ci:line -->
`<pages>/explore/`. <!-- ci:line -->
the library to WebAssembly. <!-- !ci:line -->

This is a separate SwiftPM package; Bazel ignores it.

## Building

`just explore` (`build.sh`) builds release WebAssembly, optimized for size, into `dist/`: the pages,
their stylesheet, the one `.wasm` they share, and the JavaScript that loads it, all plain files
with relative URLs. Check a page by serving that directory, for example
`python3 -m http.server -d Explore/dist 8000`, and opening `http://localhost:8000/<page>.html`.

It needs swiftly's swift.org toolchain (`EXPLORE_SWIFT`, default 6.3.3), its Swift SDK for
WebAssembly (`EXPLORE_SDK`, default `swift-6.3.3-RELEASE_wasm`; `swift sdk list`), and, to shrink
the `.wasm`, `wasm-opt` (`brew install binaryen`). If the toolchain crashes compiling a package
manifest against a newer Xcode's macOS SDK, name an older Xcode:
`EXPLORE_XCODE=/Applications/Xcode-<older>.app just explore`.

## How a page works

- `web/contents.txt` is the reading order: one `slug|title|group|summary|status` row per page.
  `page` rows have a page; `soon` rows are listed without a link.
- `web/pages/<slug>.html` starts with a `<!-- title: … -->` and a `<!-- description: … -->`
  comment; the rest is poured into `web/template.html`. Empty elements with an id (`<div
  id="app"></div>`, `<pre id="code"></pre>`) are mount points.
- `Sources/Explore/Pages/<Page>/` holds the views; `main.swift`'s `mountPage` mounts them by slug.
  `mountView(_:in:)` mounts a view on a mount point.
- Every view is drawn twice: at build time, by this package built for the build machine, into the
  page's HTML (its first frame, shown before any WebAssembly arrives), and in the browser, where
  it replaces that frame.
- The code panel shows regions of the page's own sources between `// snippet: name` and
  `// snippet end` (the Snippets plugin turns each into `Snippet.name`), so the code shown is the
  code that runs. A line ending in `// →` is followed by a result the page computed.

## Adding a page

1. A row in `web/contents.txt` and `web/pages/<slug>.html`.
2. `Sources/Explore/Pages/<Page>/`: the code it runs, marked as snippets, and the views; a case in
   `mountPage`.
3. Any module it imports in `Package.swift`'s product list.
4. `just explore`, then try it from `dist/`.

`web/vendor/browser_wasi_shim` is a vendored copy of
[browser_wasi_shim](https://github.com/bjorn3/browser_wasi_shim) (MIT or Apache-2.0), so the site
needs no bundler.
