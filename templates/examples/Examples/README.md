# Examples

Example apps for the Apple platforms ProjectName supports, as a SwiftPM package that depends on the
library by path (`..`), so the published package never depends on what the examples use.

| Path | What it is |
|---|---|
| `Sources/ExampleViews` | `ExampleView`, the SwiftUI screen the apps share, and `Greeting.example` |
| `Tests/ExampleViewsTests` | Its tests (`just examples-test`) |
| `Apps/ExampleApp` | The app: one `@main` source; Bazel applications for iPhone and iPad, Mac, visionOS and watchOS |

SwiftPM builds and tests the package (`just examples-test`). The apps need application bundles,
which SwiftPM doesn't make, so Bazel builds them from the hand-written `BUILD.bazel` files here.
Every one of those targets is `manual`, so the library's `bazel test //...` leaves them out; the
recipes name them:

| Recipe | Builds |
|---|---|
| `just example-ios` | The iPhone and iPad app, for the simulator |
| `just example-mac` | The Mac app |
| `just example-visionos` | The visionOS app, for the simulator |
| `just example-watchos` | The watchOS app, for the simulator |
| `just examples` | All four, then `just examples-test` |

`just generate` gives each app a scheme in the Xcode project. Mac Catalyst has no rules_apple rule;
to run the iOS app on a Mac, use the Mac app, or "My Mac (Designed for iPad)" from Xcode.
