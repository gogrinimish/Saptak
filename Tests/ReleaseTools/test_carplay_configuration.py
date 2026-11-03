import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('ios_release', Path(__file__).resolve().parents[2] / 'scripts/check-ios-release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class CarPlayConfigurationTests(unittest.TestCase):
    def configuration(self):
        return {'UIApplicationSceneManifest': {
            'UIApplicationSupportsMultipleScenes': True,
            'UISceneConfigurations': {'CPTemplateApplicationSceneSessionRoleApplication': [{
                'UISceneClassName': 'CPTemplateApplicationScene',
                'UISceneConfigurationName': 'Saptak CarPlay',
                'UISceneDelegateClassName': 'Saptak.CarPlaySceneDelegate',
            }]},
        }}

    def testPhoneAndCarPlayCanCoexistWithResolvedDelegateName(self):
        release.check_carplay_scene(self.configuration())

    def testMissingOrWrongSceneRoleIsRejected(self):
        for role in ['', 'UIWindowSceneSessionRoleApplication', 'CPTemplateApplicationDashboardSceneSessionRoleApplication']:
            info = self.configuration()
            config = info['UIApplicationSceneManifest']['UISceneConfigurations']
            config[role] = config.pop('CPTemplateApplicationSceneSessionRoleApplication')
            with self.subTest(role=role), self.assertRaises(ValueError):
                release.check_carplay_scene(info)

    def testSingleSceneOrUnresolvedModuleCannotPassReleaseCheck(self):
        original = self.configuration()
        for change in ['single', 'delegate', 'scene', 'duplicate']:
            info = copy.deepcopy(original)
            manifest = info['UIApplicationSceneManifest']
            entries = manifest['UISceneConfigurations']['CPTemplateApplicationSceneSessionRoleApplication']
            if change == 'single':
                manifest['UIApplicationSupportsMultipleScenes'] = False
            elif change == 'delegate':
                entries[0]['UISceneDelegateClassName'] = '$(PRODUCT_MODULE_NAME).CarPlaySceneDelegate'
            elif change == 'scene':
                entries[0]['UISceneClassName'] = 'UIWindowScene'
            else:
                entries.append(copy.deepcopy(entries[0]))
            with self.subTest(change=change), self.assertRaises(ValueError):
                release.check_carplay_scene(info)
