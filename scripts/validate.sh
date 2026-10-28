#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

build_root="${SAPTAK_BUILD_ROOT:-/tmp/SaptakValidation}"
mkdir -p "$build_root"
export CLANG_MODULE_CACHE_PATH="$build_root/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"

swift_options=(--cache-path "$build_root/PackageCache" --scratch-path "$build_root/Swift")
xcode_options=(-project Saptak.xcodeproj)
if [[ "${SAPTAK_RESTRICTED:-0}" == "1" ]]; then
    # These flags address nested tool sandboxes only; the app sandbox stays enabled.
    swift_options+=(--disable-sandbox)
    xcode_options+=(-IDEPackageSupportDisableManifestSandbox=YES 'OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox')
    export CFFIXED_USER_HOME="$build_root/XcodeUser"
fi

python3 -m unittest discover -s Tests/ReleaseTools -p 'test_*.py'
swift test "${swift_options[@]}" 2>&1 | tee "$build_root/tests.log"
xcodegen generate
xcodebuild "${xcode_options[@]}" -scheme SaptakMac \
    -destination 'platform=macOS' -derivedDataPath "$build_root/macOS" \
    build 2>&1 | tee "$build_root/macOS.log"
xcodebuild "${xcode_options[@]}" -scheme Saptak-iOS \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$build_root/iOS" \
    CODE_SIGNING_ALLOWED=NO build 2>&1 | tee "$build_root/iOS.log"

# Check built metadata, not just project labels: target-derived defaults can differ.
python3 - "$build_root" <<'PY'
from pathlib import Path
import plistlib
import sys

root = Path(sys.argv[1])
products = {
    "macOS": root / "macOS/Build/Products/Debug/Saptak.app/Contents/Info.plist",
    "iOS Simulator": root / "iOS/Build/Products/Debug-iphonesimulator/Saptak.app/Info.plist",
}
for platform, path in products.items():
    with path.open("rb") as handle:
        info = plistlib.load(handle)
    for key in ("CFBundleDisplayName", "CFBundleName", "CFBundleExecutable"):
        if info.get(key) != "Saptak":
            raise SystemExit(f"{platform}: {key} must be Saptak, got {info.get(key)!r}")
    if info.get("CFBundleIdentifier") != "com.playsaptak.app":
        raise SystemExit(f"{platform}: unexpected bundle ID {info.get('CFBundleIdentifier')!r}")
    if platform == "iOS Simulator" and info.get("UIBackgroundModes") != ["audio"]:
        raise SystemExit("iOS Simulator: UIBackgroundModes must contain the audio background mode")
    resources = path.parent / "Resources" if platform == "macOS" else path.parent
    for name in ("Alice-Regular.ttf", "OFL.txt"):
        bundled = resources / "Fonts" / name
        if not bundled.is_file() or bundled.read_bytes() != (Path("App/Fonts") / name).read_bytes():
            raise SystemExit(f"{platform}: missing or mismatched bundled font/license: {name}")
    if platform == "iOS Simulator" and info.get("UIAppFonts") != ["Fonts/Alice-Regular.ttf"]:
        raise SystemExit("iOS Simulator: custom-font registration metadata is missing")
    print(f"{platform}: verified Saptak / com.playsaptak.app and licensed font resources")
PY
python3 scripts/check-ios-release.py "$build_root/iOS/Build/Products/Debug-iphonesimulator/Saptak.app"
