import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('public_release', Path(__file__).resolve().parents[2] / 'scripts/prepare-public-release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class PublicReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'source'
        self.root.mkdir()
        self.root = self.root.resolve()
        for name in release.EXACT_FILES:
            self.write(name, 'Public documentation\n')

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def testPrivateWorkingFilesAndPersonalAudioAreExcluded(self):
        for name in ['AGENTS.md', '.local/release/signing.xcconfig', 'docs/STATUS.md',
                     'docs/STATUS_HISTORY.md', 'docs/DESIGN.md', 'docs/design/mock.svg',
                     'Tests/personal.m4a', 'scripts/render-design-palettes.py',
                     'Config/ExportOptions.plist', 'App/private-account.json',
                     'docs/GROWTH.md', '.local/strategy/marketing/GROWTH.md']:
            self.write(name, 'Private working data')
        self.write('App/Example.swift', 'import Foundation')
        self.write('Config/LocalSigning.xcconfig', '#include? "../.local/release/signing.xcconfig"')
        names = [p.relative_to(self.root).as_posix() for p in release.collect_files(self.root)]
        self.assertIn('App/Example.swift', names)
        self.assertNotIn('docs/GROWTH.md', names)
        self.assertNotIn('.local/strategy/marketing/GROWTH.md', names)
        self.assertEqual(set(names), set(release.EXACT_FILES) | {'App/Example.swift', 'Config/LocalSigning.xcconfig'})

    def testSymlinkedSourceCannotLeakOutsideFiles(self):
        target = self.write('private.txt', 'Private')
        directory = self.root / 'App'
        directory.mkdir(exist_ok=True)
        (directory / 'Leak.swift').symlink_to(target)
        with self.assertRaises(ValueError):
            release.collect_files(self.root)

    def testPrivateKeyMarkerFailsPreflight(self):
        self.write('App/Leak.swift', '-----BEGIN ' + 'PRIVATE KEY-----')
        with self.assertRaises(ValueError):
            release.collect_files(self.root)

    def testPersonalHomePathFailsPreflight(self):
        self.write('App/Leak.swift', '/' + 'Users/' + 'someone/private-file')
        with self.assertRaises(ValueError):
            release.collect_files(self.root)

    def testExistingDestinationIsNotOverwritten(self):
        destination = Path(self.temp.name) / 'preview'
        destination.mkdir()
        sentinel = destination / 'keep.txt'
        sentinel.write_text('Keep')
        with self.assertRaises(ValueError):
            release.export(self.root, destination)
        self.assertEqual(sentinel.read_text(), 'Keep')

    def testExportIncludesInventoryAndOnlySyntheticFixture(self):
        self.write(release.SYNTHETIC_AUDIO, 'Synthetic fixture')
        self.write('Tests/secret.opus', 'Private')
        destination = Path(self.temp.name) / 'preview'
        names = release.export(self.root, destination)
        self.assertIn(release.SYNTHETIC_AUDIO, names)
        self.assertFalse((destination / 'Tests/secret.opus').exists())
        self.assertEqual((destination / 'PUBLIC_FILES.txt').read_text().splitlines(), names)

    def testCannotExportInsideWorkingRepository(self):
        with self.assertRaises(ValueError):
            release.export(self.root, self.root / 'nested-preview')


if __name__ == '__main__':
    unittest.main()
