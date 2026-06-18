fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios certs

```sh
[bundle exec] fastlane ios certs
```

Sync certificates and provisioning profiles to ~/Library/MobileDevice

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Capture App Store screenshots on simulators

### ios whatif

```sh
[bundle exec] fastlane ios whatif
```

Preview what the next beta changelog would look like

### ios changelog

```sh
[bundle exec] fastlane ios changelog
```

Print commits since a beta build number: fastlane changelog since:7

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build and upload to TestFlight

### ios release

```sh
[bundle exec] fastlane ios release
```

Full release: build + upload metadata + screenshots + submit for review

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
