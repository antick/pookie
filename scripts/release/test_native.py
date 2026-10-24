"""Compile actual Mach-O fixtures: an Intel helper must never ship unnoticed."""
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

try:
    import native
except ImportError:
    native = None


class NativeReleaseTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(native, 'Native release validation is missing')
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.app = Path(self.temp.name) / 'Fixture.app'
        (self.app / 'Contents/MacOS').mkdir(parents=True)
        (self.app / 'Contents/Helpers').mkdir()
        (self.app / 'Contents/Info.plist').write_bytes(plistlib.dumps(dict(
            CFBundleIdentifier='test.pookie.fixture', CFBundleExecutable='Fixture',
            CFBundleName='Fixture', CFBundlePackageType='APPL')))
        self.source = Path(self.temp.name) / 'fixture.c'
        self.source.write_text('int main(void) { return 0; }\n')
        self.compile(self.app / 'Contents/MacOS/Fixture', 'arm64')

    def compile(self, output, *architectures):
        args = ['xcrun', 'clang', str(self.source), '-o', str(output)]
        for architecture in architectures:
            args += ['-arch', architecture]
        subprocess.run(args, check=True, capture_output=True)

    def test_arm64_main_does_not_hide_intel_helper(self):
        self.compile(self.app / 'Contents/Helpers/Intel', 'x86_64')
        with self.assertRaisesRegex(ValueError, 'x86_64'):
            native.verify_architectures(self.app)

    def test_thin_then_sign_preserves_symlinks(self):
        helper = self.app / 'Contents/Helpers/Universal'
        self.compile(helper, 'arm64', 'x86_64')
        link = helper.with_name('Current')
        link.symlink_to(helper.name)
        native.sign_bundle(self.app, '-', production=False)
        self.assertEqual(native.verify_architectures(self.app), 2)
        self.assertTrue(link.is_symlink())
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(self.app)], check=True)

    def test_intel_only_helper_cannot_be_thinned_or_signed(self):
        self.compile(self.app / 'Contents/Helpers/Intel', 'x86_64')
        with self.assertRaisesRegex(ValueError, 'Apple silicon'):
            native.sign_bundle(self.app, '-', production=False)

    def test_production_refuses_ad_hoc_signature(self):
        with self.assertRaisesRegex(ValueError, 'Developer ID'):
            native.sign_bundle(self.app, '-', production=True)

    def test_symlink_outside_bundle_is_rejected(self):
        (self.app / 'Contents/Helpers/Escape').symlink_to('/bin/ls')
        with self.assertRaisesRegex(ValueError, 'symlink'):
            native.verify_architectures(self.app)


if __name__ == '__main__':
    unittest.main()
