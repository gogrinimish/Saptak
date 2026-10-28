# Contributing to Saptak

Keep Saptak native, private and simple. User-owned audio stays in its original location. Do not introduce an account, backend, telemetry, permanent audio import or new dependency without discussing the design first.

## Build and test

Use Xcode, Swift 5.9-compatible language mode and XcodeGen. Run `scripts/validate.sh` before submitting changes. It regenerates the project; edit `project.yml` rather than the generated project. See [testing](docs/TESTING.md) for individual commands and manual acceptance.

Use temporary synthetic fixtures, clean them with `defer`, and test observable behavior: folder hierarchy, queue transitions, failures, cancellation and original-file preservation. Keep platform-specific APIs out of SaptakCore. Do not equate SDK compilation or offscreen layout tests with native/device validation.

## Style and responsibilities

Use four-space indentation, UpperCamelCase types, lowerCamelCase members, descriptive XCTest methods beginning with `test`, and main-actor isolation for UI state. No linter is configured. Avoid unrelated reformatting.

Balance security-scoped access, renew stale bookmarks and preserve saved selection on transient errors. Keep file reads coordinated. Report inaccessible folders without hiding readable tracks. Selecting a track starts the displayed playlist at that row. Keep the approved accessible typography, semantic colors and native controls consistent.

## Changes and pull requests

Use focused, imperative commit messages. Explain the resulting behavior, relevant validation, remaining limitations and related issues. Include screenshots for UI changes. Update public documentation when behavior changes.

Never include personal recordings, absolute home paths, session logs, credentials, signing configuration, certificates, archives or Xcode user state. Local working notes and release credentials are ignored. Public documentation should describe reproducible behavior and architecture rather than individual development sessions.
