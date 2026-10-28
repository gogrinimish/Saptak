#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

archive_root="${SAPTAK_ARCHIVE_ROOT:-/tmp/SaptakRelease}"
mkdir -p "$archive_root"
export CLANG_MODULE_CACHE_PATH="$archive_root/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
options=(-project Saptak.xcodeproj -scheme Saptak-iOS -configuration Release
    -destination 'generic/platform=iOS' -derivedDataPath "$archive_root/DerivedData"
    -packageCachePath "$archive_root/PackageCache")
if [[ "${SAPTAK_RESTRICTED:-0}" == "1" ]]; then
    options+=(-IDEPackageSupportDisableManifestSandbox=YES 'OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox')
fi
if [[ "${1:-}" == "--unsigned" && "$#" == "1" ]]; then
    archive_path="$archive_root/Saptak-iOS-unsigned.xcarchive"
    if [[ "${SAPTAK_RESTRICTED:-0}" == "1" ]]; then
        export CFFIXED_USER_HOME="$archive_root/XcodeUser"
    fi
    options+=(CODE_SIGNING_ALLOWED=NO)
    echo 'Building an unsigned archive for packaging validation; it cannot be uploaded to TestFlight.'
elif [[ "$#" == "0" ]]; then
    signing_config="${SAPTAK_SIGNING_CONFIG:-.local/release/signing.xcconfig}"
    if [[ ! -f "$signing_config" ]]; then
        echo 'Missing private signing configuration; see docs/RELEASING.md.' >&2
        exit 1
    fi
    archive_path="$archive_root/Saptak-iOS.xcarchive"
    options+=(-xcconfig "$signing_config" -allowProvisioningUpdates)
else
    echo 'Usage: archive-ios.sh [--unsigned]' >&2
    exit 2
fi
if [[ -e "$archive_path" ]]; then
    echo 'Archive destination already exists; choose a new SAPTAK_ARCHIVE_ROOT.' >&2
    exit 1
fi
xcodegen generate
xcodebuild "${options[@]}" -archivePath "$archive_path" archive
python3 scripts/check-ios-release.py "$archive_path/Products/Applications/Saptak.app"
echo "Archive prepared at $archive_path. No upload performed."
