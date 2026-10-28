# Testing

## Automated validation

```sh
scripts/validate.sh
```

This runs Swift package tests, regenerates the Xcode project, builds the Mac app with local signing enabled, builds an unsigned iOS Simulator app and validates processed bundle metadata. Build products/logs default to `/tmp/SaptakValidation`; `SAPTAK_BUILD_ROOT` overrides this location.

```sh
xcodebuild -project Saptak.xcodeproj -scheme SaptakMac -destination 'platform=macOS' -derivedDataPath /tmp/SaptakValidation/macOS build
xcodebuild -project Saptak.xcodeproj -scheme Saptak-iOS -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/SaptakValidation/iOS CODE_SIGNING_ALLOWED=NO build
```

In restricted automation, `SAPTAK_RESTRICTED=1` redirects tool caches and disables nested compiler/package sandboxes for that invocation. It never disables app sandbox entitlements. Native file coordination tests are opt-in:

```sh
SAPTAK_NATIVE_INTEGRATION=1 swift test --filter testNativeFileCoordinationIntegration
```

A skipped integration test is not a native-service pass. Tests use isolated defaults and synthetic files, never personal audio. Fixture-generation instructions are in the fixture directory.

## Manual acceptance

Record platform/OS, build, source provider, codec/container and result for each check. Use disposable audio folders. SDK builds and offscreen layout tests do not replace these checks.

- Select a folder, cancel/reopen the picker, quit/relaunch and verify saved access.
- Browse nested/empty folders, use parent breadcrumbs/Back/root navigation, refresh additions/removals and check hierarchy/counts.
- On iPhone, scroll the last track fully above the compact player at the root and after several folder pushes, including long titles and large text. Verify summary/folder/track separators share the same inset.
- Exercise unavailable folders, cloud-only tracks, retry and selection changes during slow provider operations.
- Start from a middle track; test recursive Play all, queue selection, shuffle/order restoration and repeat-off/all/one.
- Seek and pause/resume during playback/loading; verify Previous, Next, errors and recovery.
- Check Now Playing metadata, system controls/media keys, ownership transfer and cleanup. Validate iPhone background/lock-screen controls separately.
- Test actual AirPlay hardware; compare another local audio app when diagnosing a route failure.
- Compare hashes, modification times and directory/container contents before/after playback and relaunch; originals must remain unchanged without permanent imports.
- Check compact/large windows, rapid resizing, VoiceOver, keyboard, contrast and Dynamic Type.
- Repeat on minimum supported OS versions and representative codecs/providers.

## Publication tooling

```sh
python3 -m unittest discover -s Tests/ReleaseTools -p 'test_*.py'
python3 scripts/prepare-public-release.py /tmp/SaptakPublicPreview
```

The preview uses an explicit allowlist and refuses to overwrite an existing destination. Review it before publishing; it is not a substitute for reviewing Git's staged files/history.
