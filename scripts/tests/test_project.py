"""Portable structural checks; these do NOT compile an iOS application."""
import importlib.util
import plistlib
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class ProjectTests(unittest.TestCase):
    def test_openable_project_and_shared_scheme_exist(self):
        self.assertTrue((ROOT / 'ios/PocketCard.xcodeproj/project.pbxproj').is_file())
        scheme = ROOT / 'ios/PocketCard.xcodeproj/xcshareddata/xcschemes/PocketCard.xcscheme'
        self.assertTrue(scheme.is_file())
        root = ET.parse(scheme).getroot()
        self.assertEqual(len(root.findall('.//TestableReference')), 1)
        self.assertEqual(root.find('.//TestableReference/BuildableReference').attrib['BlueprintName'], 'PocketCardTests')

    def test_generator_matches_checked_in_project(self):
        path = ROOT / 'scripts/generate_xcode_project.py'
        self.assertTrue(path.is_file())
        spec = importlib.util.spec_from_file_location('project_generator', path)
        generator = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(generator)
        content, graph = generator.build_project(ROOT)
        actual = (ROOT / 'ios/PocketCard.xcodeproj/project.pbxproj').read_text()
        self.assertEqual(actual, content)
        refs = [v for v in graph['objects'].values() if v.get('isa') == 'PBXFileReference']
        native_paths = {v['path'] for v in refs if v.get('lastKnownFileType') == 'sourcecode.swift'}
        expected = {p.relative_to(ROOT / 'ios').as_posix() for p in (ROOT / 'ios').glob('PocketCard*/*.swift')}
        self.assertEqual(native_paths, expected)
        targets = [v for v in graph['objects'].values() if v.get('isa') == 'PBXNativeTarget']
        self.assertEqual({t['name'] for t in targets}, {'PocketCard', 'PocketCardTests'})
        self.assertTrue(all(t['packageProductDependencies'] for t in targets))

    def test_default_config_has_no_wallet_entitlement(self):
        path = ROOT / 'ios/Configurations/Base.xcconfig'
        self.assertTrue(path.is_file())
        text = path.read_text()
        self.assertIn('WALLET_ACCESS_ENABLED = NO', text)
        self.assertIn('PC_APP_ENTITLEMENTS =\n', text)
        self.assertFalse((ROOT / 'ios/Local.xcconfig').exists())

    def test_privacy_and_app_identity_resources(self):
        path = ROOT / 'ios/PocketCard/Info.plist'
        self.assertTrue(path.is_file())
        info = plistlib.loads(path.read_bytes())
        self.assertEqual(info['PocketCardTeamIdentifier'], '$(DEVELOPMENT_TEAM)')
        self.assertNotIn('NSAllowsArbitraryLoads', str(info))
        privacy = plistlib.loads((ROOT / 'ios/PocketCard/PrivacyInfo.xcprivacy').read_bytes())
        self.assertFalse(privacy['NSPrivacyTracking'])
        self.assertEqual(privacy['NSPrivacyCollectedDataTypes'], [])
        entitlements = plistlib.loads((ROOT / 'ios/PocketCard/PocketCard.entitlements').read_bytes())
        self.assertEqual(entitlements['com.apple.developer.pass-type-identifiers'],
                         ['$(TeamIdentifierPrefix)$(WALLET_PASS_TYPE_ID)'])


if __name__ == '__main__':
    unittest.main()
