#!/usr/bin/env python3
"""Check release metadata in a processed iOS app bundle (not upload validation)."""
import plistlib
from pathlib import Path
import re
import sys


def check(bundle):
    bundle = Path(bundle)
    with (bundle / 'Info.plist').open('rb') as handle:
        info = plistlib.load(handle)
    for key in ('CFBundleDisplayName', 'CFBundleName', 'CFBundleExecutable'):
        if info.get(key) != 'Saptak':
            raise ValueError(f'Unexpected {key}')
    if info.get('CFBundleIdentifier') != 'com.playsaptak.app':
        raise ValueError('Unexpected bundle identifier')
    if not re.fullmatch(r'\d+\.\d+(?:\.\d+)?', str(info.get('CFBundleShortVersionString', ''))):
        raise ValueError('Missing or invalid release version')
    if not re.fullmatch(r'\d+(?:\.\d+){0,2}', str(info.get('CFBundleVersion', ''))):
        raise ValueError('Missing or invalid build number')
    if info.get('UIBackgroundModes') != ['audio']:
        raise ValueError('Background audio mode missing')
    if not isinstance(info.get('UILaunchScreen'), dict):
        raise ValueError('Launch-screen definition missing')
    if not isinstance(info.get('UIApplicationSceneManifest'), dict):
        raise ValueError('Scene manifest missing')
    orientations = info.get('UISupportedInterfaceOrientations~ipad', [])
    required = {'UIInterfaceOrientationPortrait', 'UIInterfaceOrientationPortraitUpsideDown',
                'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight'}
    if not required.issubset(orientations):
        raise ValueError('iPad orientations incomplete')
    if info.get('ITSAppUsesNonExemptEncryption') is not False:
        raise ValueError('Review the encryption declaration')
    with (bundle / 'PrivacyInfo.xcprivacy').open('rb') as handle:
        privacy = plistlib.load(handle)
    if privacy.get('NSPrivacyTracking') is not False or privacy.get('NSPrivacyCollectedDataTypes') != []:
        raise ValueError('Privacy manifest does not match current no-tracking/no-collection behavior')
    expected = {'NSPrivacyAccessedAPIType': 'NSPrivacyAccessedAPICategoryUserDefaults',
                'NSPrivacyAccessedAPITypeReasons': ['CA92.1']}
    if expected not in privacy.get('NSPrivacyAccessedAPITypes', []):
        raise ValueError('App-only UserDefaults reason missing')
    return info


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: check-ios-release.py /path/to/Saptak.app')
    try:
        info = check(sys.argv[1])
    except (ValueError, OSError, plistlib.InvalidFileException) as error:
        raise SystemExit(str(error))
    print(f"iOS release metadata passed: {info['CFBundleShortVersionString']} ({info['CFBundleVersion']})")


if __name__ == '__main__':
    main()
