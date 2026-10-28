#!/usr/bin/env python3
"""Create a reviewable public source preview without private working files."""
import argparse
from pathlib import Path
import re
import shutil

EXACT_FILES = (
    '.gitignore', 'LICENSE', 'README.md', 'CONTRIBUTING.md', 'Package.swift', 'project.yml',
    'docs/ARCHITECTURE.md', 'docs/ROADMAP.md', 'docs/TESTING.md', 'docs/PRIVACY.md', 'docs/RELEASING.md', 'docs/SCREENSHOTS.md',
    'scripts/validate.sh', 'scripts/archive-ios.sh', 'scripts/check-ios-release.py',
    'scripts/capture-store-screenshots.py', 'scripts/normalize-screenshots.swift',
    'docs/images/iphone-library.png', 'docs/images/iphone-player.png', 'docs/images/mac-library.png',
    'App/Fonts/Alice-Regular.ttf', 'App/Fonts/OFL.txt',
    'site/guides/play-your-own-audio-on-iphone.html', 'docs/WEBSITE.md', 'site/index.html', 'site/sitemap.xml', 'site/privacy.html', 'site/styles.css', 'site/.nojekyll',
    'site/assets/fonts/Alice-Regular.ttf', 'site/assets/fonts/OFL.txt',
    'site/assets/icon.svg', 'site/assets/iphone-library.png', 'site/assets/iphone-player.png', 'site/assets/mac-library.png',
    'scripts/prepare-public-release.py', 'scripts/generate-app-icons.py', 'scripts/probe-codecs.swift',
)
DIRECTORIES = ('App', 'Sources', 'Tests', 'Config', 'Design')
EXTENSIONS = {'.swift', '.entitlements', '.xcprivacy', '.json', '.plist', '.svg', '.py'}
SYNTHETIC_AUDIO = 'Tests/SaptakPlatformTests/Fixtures/tone.m4a'
TEXT_EXTENSIONS = EXTENSIONS | {'.md', '.sh', '.yml', '.xcconfig'}
SENSITIVE = (
    re.compile(r'/(?:Users|home)/[A-Za-z0-9_.-]+/'),
    re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
    re.compile(r'\bgh[pousr]_[A-Za-z0-9]{30,}\b'),
    re.compile(r'\bgithub_pat_[A-Za-z0-9_]{30,}\b'),
)


def collect_files(root):
    root = Path(root).resolve()
    files = []
    for name in EXACT_FILES:
        path = root / name
        if path.is_symlink() or not path.is_file():
            raise ValueError(f'Missing or unsafe public file: {name}')
        files.append(path)
    for directory in DIRECTORIES:
        base = root / directory
        if base.is_symlink():
            raise ValueError(f'Symlinked source directory: {directory}')
        if not base.exists():
            continue
        for path in base.rglob('*'):
            if path.is_symlink():
                raise ValueError(f'Symlinks are not allowed in the preview: {path.relative_to(root)}')
            if not path.is_file() or any(part.startswith('.') or part == '__pycache__' for part in path.relative_to(base).parts):
                continue
            name = path.relative_to(root).as_posix()
            asset = name.startswith('App/Assets.xcassets/') and path.suffix in {'.png', '.json'}
            fixture_note = name == 'Tests/SaptakPlatformTests/Fixtures/README.md'
            source = directory in {'App', 'Sources', 'Tests'} and path.suffix == '.swift'
            app_config = directory == 'App' and path.suffix in {'.entitlements', '.xcprivacy'}
            release_test = name.startswith('Tests/ReleaseTools/test_') and path.suffix == '.py'
            config = name in {'Config/iOS-Info.plist', 'Config/LocalSigning.xcconfig'}
            design = name in {'Design/AppIcon.svg', 'Design/AppIcon-macOS.svg'}
            if source or app_config or release_test or config or design or asset or fixture_note or name == SYNTHETIC_AUDIO:
                files.append(path)
    for path in files:
        if path.suffix in TEXT_EXTENSIONS or path.name == '.gitignore':
            text = path.read_text(encoding='utf-8')
            if any(pattern.search(text) for pattern in SENSITIVE):
                raise ValueError(f'Potential private content in {path.relative_to(root)}; review before publishing')
    return sorted(set(files))


def export(root, destination):
    root = Path(root).resolve()
    destination = Path(destination).absolute()
    if destination.exists() or destination.is_symlink():
        raise ValueError('Destination already exists; refusing to overwrite it')
    if destination.resolve().is_relative_to(root):
        raise ValueError('Choose a destination outside the working repository')
    files = collect_files(root)
    destination.mkdir(parents=True)
    names = []
    for source in files:
        name = source.relative_to(root)
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        target.chmod(0o755 if source.stat().st_mode & 0o100 else 0o644)
        names.append(name.as_posix())
    (destination / 'PUBLIC_FILES.txt').write_text('\n'.join(names) + '\n', encoding='utf-8')
    return names


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination', type=Path, help='New directory outside this working copy')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    try:
        names = export(root, args.destination)
    except (ValueError, OSError) as error:
        parser.exit(1, f'{error}\n')
    print(f'Prepared {len(names)} public files in {args.destination}; review PUBLIC_FILES.txt before publishing.')


if __name__ == '__main__':
    main()
