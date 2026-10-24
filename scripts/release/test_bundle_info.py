import plistlib
from pathlib import Path
import tempfile
import unittest

try:
    import bundle_info
except ImportError:
    bundle_info = None

from test_policy import info


class BundleIdentityTests(unittest.TestCase):
    def test_development_bundle_is_separate_and_has_no_update_feed(self):
        self.assertIsNotNone(bundle_info, 'Bundle identity preparation is missing')
        metadata = bundle_info.for_channel(info(), 'development')
        self.assertEqual(metadata['CFBundleIdentifier'], 'com.pookie.pet.dev')
        self.assertEqual(metadata['PookieChannel'], 'development')
        self.assertEqual(metadata['CFBundleName'], 'Pookie Dev')
        self.assertEqual(metadata['CFBundleDisplayName'], 'Pookie Dev')
        self.assertNotIn('SUFeedURL', metadata)
        self.assertNotIn('SUPublicEDKey', metadata)
        self.assertFalse(metadata['SUEnableAutomaticChecks'])
        self.assertEqual(metadata['CFBundleVersion'], '12')

    def test_production_uses_canonical_metadata(self):
        self.assertIsNotNone(bundle_info, 'Bundle identity preparation is missing')
        self.assertEqual(bundle_info.for_channel(info(), 'production'), info() | {'CFBundleIconFile': 'AppIcon'})

    def test_unknown_channel_is_rejected(self):
        self.assertIsNotNone(bundle_info, 'Bundle identity preparation is missing')
        with self.assertRaises(ValueError):
            bundle_info.for_channel(info(), 'prodution')


if __name__ == '__main__':
    unittest.main()
