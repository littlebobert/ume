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

### ios bootstrap_signing

```sh
[bundle exec] fastlane ios bootstrap_signing
```

Create or repair Ume's App Store signing assets from a trusted Mac

### ios sync_signing

```sh
[bundle exec] fastlane ios sync_signing
```

Install Ume's existing App Store signing assets without changing them

### ios release

```sh
[bundle exec] fastlane ios release
```

Build a signed App Store archive and upload it to TestFlight

----


## Mac

### mac bootstrap_signing

```sh
[bundle exec] fastlane mac bootstrap_signing
```

Create or repair Ume's Developer ID signing assets from a trusted Mac

### mac sync_signing

```sh
[bundle exec] fastlane mac sync_signing
```

Install Ume's existing Developer ID signing assets without changing them

### mac release

```sh
[bundle exec] fastlane mac release
```

Build a signed Developer ID app for notarization

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
