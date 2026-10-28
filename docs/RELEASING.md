# Release Preparation

## Build metadata and privacy

Edit versions in `project.yml`, regenerate with XcodeGen, and increment the build number for each upload. The same `com.playsaptak.app` identifier is used by the native Mac and iOS apps. Do not change it casually: saved permissions and distribution records depend on identity.

The generated iOS plist includes background audio, a launch-screen definition, supported orientations and an encryption declaration matching the current native-only implementation. The app includes a UserDefaults privacy manifest. Revisit both declarations when adding features/dependencies.

## iOS archive and TestFlight

```sh
scripts/validate.sh
scripts/archive-ios.sh --unsigned
```

The unsigned archive verifies device-SDK compilation and packaging; it cannot be uploaded or installed through TestFlight. For a signed archive, configure an enrolled team in Xcode or create ignored `.local/release/signing.xcconfig`:

```text
DEVELOPMENT_TEAM = YOUR_TEAM_ID
CODE_SIGN_STYLE = Automatic
```

```sh
scripts/archive-ios.sh
```

The iOS target optionally includes that private file through Config/LocalSigning.xcconfig, so Xcode regeneration preserves local team selection without publishing it. The helper uses the same private file and permits Xcode to update signing assets. It does not upload automatically. With signing/account access available, open the archive in Xcode Organizer, choose App Store Connect distribution, validate and upload. The corresponding app record/bundle ID must exist in the intended team. After processing, assign the build to an internal TestFlight group and install it from TestFlight. External testing can require beta review.

Never commit a team/account configuration, certificate, private key, provisioning profile, archive or API credential. Build artifacts default to `/tmp/SaptakRelease`. See [Apple's upload guide](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds) and [TestFlight tutorial](https://developer.apple.com/tutorials/develop-in-swift/test-your-beta-app).

## Store screenshots

See [screenshot capture](SCREENSHOTS.md) for isolated debug capture, synthetic audio, platform dimensions and review. Actual captures stay private until selected for submission; screenshot preparation does not upload assets or submit the app.

## Public source release

Run `scripts/prepare-public-release.py` to create a new allowlisted preview directory. Only source, synthetic fixtures, final design assets, public docs and selected tooling are exported. Local instructions, status/history, design experiments, account data, user state and distribution artifacts are excluded.

Review the file inventory and contents before creating a public repository. Do not blindly publish the working directory or assume `.gitignore` removes already tracked content/history. Retain the MIT license, verify fixture/asset provenance and avoid personal recordings. No publishing destination or credentials are stored in this repository.

## Store listing and native Mac release

Use the live marketing, [support](https://gogrinimish.github.io/Saptak/support.html) and [privacy](https://gogrinimish.github.io/Saptak/privacy.html) URLs. Privacy/support links are available inside the app; Mac also exposes them through Help. Retain platform-specific review instructions, since Mac uses Finder/sidebar navigation while iOS uses Files/hierarchical navigation. The existing bundle identifier is shared across native platforms; configure their versions under the intended App Store Connect record.

For a native Mac archive, use the SaptakMac scheme with a configured Apple team and automatic signing:

```sh
xcodebuild -project Saptak.xcodeproj -scheme SaptakMac -configuration Release -destination 'generic/platform=macOS' -archivePath /tmp/SaptakRelease/Saptak-macOS.xcarchive -xcconfig .local/release/signing.xcconfig -allowProvisioningUpdates archive
```

Use App Store Connect distribution when exporting. Do not mark a build internal-TestFlight-only if it is intended for App Review. Upload success means delivery was accepted; confirm processing completed and select the matching version/build separately for each platform. Review screenshots, privacy answers, age/content declarations, contact details, price/territories and release timing before submitting. Account-holder declarations and private review contacts do not belong in this repository.
