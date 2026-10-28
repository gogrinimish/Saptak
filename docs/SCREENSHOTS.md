# App Store Screenshots

Capture actual app UI with synthetic, silent audio. Do not use personal libraries, recordings, provider accounts or unpublished Cast functionality. Screenshots are reviewable release assets, not proof of device/provider acceptance.

## Capture setup

`ScreenshotCapture.swift` is compiled only for DEBUG. Explicit launch flags select isolated preferences and a generated library, then navigate the actual SwiftUI views and play a real silent AAC fixture. It does not inject a production library, claim native media controls, or run without the capture arguments. Release builds exclude the capture code.

Build the normal debug iOS Simulator app and a separately identified, sandboxed Mac capture app. Keep app entitlements enabled. For Mac capture only, override PRODUCT_BUNDLE_IDENTIFIER to com.playsaptak.screenshots in the build invocation; never change the production identity in project.yml. This isolates the normal app's preferences/container.

```sh
scripts/validate.sh
xcodebuild -project Saptak.xcodeproj -scheme SaptakMac -destination 'platform=macOS' -derivedDataPath /tmp/SaptakScreenshotMac PRODUCT_BUNDLE_IDENTIFIER=com.playsaptak.screenshots build
python3 scripts/capture-store-screenshots.py --output .local/release/screenshots/review --ios-app /tmp/SaptakValidation/iOS/Build/Products/Debug-iphonesimulator/Saptak.app --mac-app /tmp/SaptakScreenshotMac/Build/Products/Debug/Saptak.app --devices iphone iphone-max ipad
```

The script requires native simulator/window access. Mac capture uses `screencapture` with the isolated app's window ID; allow Screen Recording for the invoking terminal if macOS requests it, then restart that terminal if required. Only the app window is captured, without the desktop or other apps. It creates and deletes its own simulator devices, uses generated audio, refuses to overwrite an existing output directory, and captures a separate Mac process. It never resets an existing simulator or the normal app's defaults. Inspect local invocation/cache requirements in the validation script for restricted environments.

## Screens and sizes

- Library: hierarchy, recursive folder counts and compact playback.
- Folder: real folder playlist and selected track.
- Player (iOS): expanded controls, progress, repeat and native AirPlay action.
- Up Next: previous/current/upcoming tracks in playback order.
- Search: matches across folders, with relative paths.
- Welcome: logo, tagline, folder selection and optional cloud-folder help.

The current capture profiles use portrait iPhone Dynamic Island medium, optional large iPhone, 13-inch iPad, and 1440×900 Mac. The script retains original captures, exports opaque sRGB PNGs at identical dimensions into app-store/ through the native ImageIO tool, validates dimensions/alpha channels, and writes a local HTML review gallery plus a JSON inventory. This is file-format normalization, not UI retouching. Generated assets and diagnostic logs stay under ignored .local/release; they are not automatically published or uploaded.

Check [Apple's screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications) before each submission. The reviewed requirements call for an iPhone Dynamic Island medium screenshot, a 13-inch iPad screenshot when iPad is supported, and 16:10 Mac images for a Mac listing. Images must be opaque. Capture each platform rather than stretching another platform's UI.

## Review and submission

Review every image for loading/error overlays, clipped controls, readable typography, correct branding and fictional file names. Confirm the same visible features exist in the submitted release build. Do not advertise Cast, explicit offline guarantees, unsupported provider compatibility or unverified accessibility claims. Upload the selected image sets only after review; retain original captures and the manifest for reproducibility.

Three reviewed, opaque screenshots are explicitly included under `docs/images` for the README and mirrored under `site/assets` for the website. Refresh these from the latest approved capture set when visible UI changes. Keep the full store inventory, original captures, generated audio and logs out of the public-source export.
