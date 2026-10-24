"""Release boundaries use real temporary source trees and archives."""
import base64
import hashlib
import os
from pathlib import Path
import plistlib
import subprocess
import shutil
import sys
import tempfile
import tarfile
import io
import unittest
import zipfile

try:
    import policy
except ImportError:
    policy = None


def info():
    return dict(CFBundleShortVersionString='1.2.3', CFBundleVersion='12',
                CFBundleIdentifier='com.pookie.pet', CFBundleExecutable='Pookie',
                PookieChannel='production', LSMinimumSystemVersion='14.0',
                SURequireSignedFeed=True, SUVerifyUpdateBeforeExtraction=True,
                SUSignedFeedFailureExpirationInterval=0,
                SUFeedURL='https://antick.github.io/pookie/appcast.xml',
                SUPublicEDKey=base64.b64encode(bytes(range(32))).decode())


class ReleasePolicyTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(policy, 'Release policy implementation is missing')
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'Resources').mkdir()
        self.metadata = info()
        self.write_info()

    def write_info(self):
        (self.root / 'Resources/Info.plist').write_bytes(plistlib.dumps(self.metadata))

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.root), *args],
                                       stderr=subprocess.DEVNULL, text=True).strip()

    def source(self):
        self.git('init', '-b', 'main')
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.git('config', 'user.name', 'Release fixture')
        (self.root / 'CHANGELOG.md').write_text('## [1.2.3] - 2026-10-24\n\n- Test release.\n')
        (self.root / 'Package.swift').write_text(
            '.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")')
        (self.root / 'Package.resolved').write_text(
            '{"pins":[{"identity":"sparkle","state":{"version":"2.10.0"}}]}')
        self.git('add', '.')
        self.git('commit', '-m', 'fixture')
        self.git('tag', 'v1.2.3')
        self.git('update-ref', 'refs/remotes/origin/main', 'HEAD')

    def feed(self):
        name = 'Pookie-1.2.3-arm64.zip'
        archive = self.root / name
        with zipfile.ZipFile(archive, 'w') as output:
            output.writestr('Pookie.app/Contents/Info.plist', plistlib.dumps(self.metadata))
        signature = base64.b64encode(bytes(range(64))).decode()
        xml = f'''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
          <sparkle:version>12</sparkle:version><sparkle:shortVersionString>1.2.3</sparkle:shortVersionString>
          <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
          <enclosure url="https://github.com/antick/pookie/releases/download/v1.2.3/{name}"
          length="{archive.stat().st_size}" sparkle:edSignature="{signature}" type="application/octet-stream"/>
          </item></channel></rss>'''
        path = self.root / 'appcast.xml'
        path.write_text(xml)
        return path

    def assets(self):
        self.feed()
        (self.root / 'Pookie-1.2.3-arm64.dmg').write_bytes(b'disk image fixture')
        with tarfile.open(self.root / 'Pookie-1.2.3-source.tar.gz', 'w:gz') as output:
            for name in policy.SOURCE_FILES:
                data = (plistlib.dumps(self.metadata) if name == 'Resources/Info.plist'
                        else b'corresponding source fixture')
                member = tarfile.TarInfo('Pookie-1.2.3/' + name)
                member.size = len(data)
                output.addfile(member, io.BytesIO(data))
        self.checksums()

    def checksums(self):
        names = policy.asset_names(self.metadata)
        (self.root / 'SHA256SUMS').write_text(''.join(
            f'{hashlib.sha256((self.root / name).read_bytes()).hexdigest()}  {name}\n'
            for name in names if name != 'SHA256SUMS'))

    def test_feed_signature_failures_never_expire(self):
        for value in (1, 1728000, -1, '0', None):
            with self.subTest(value=value):
                metadata = info()
                if value is None:
                    metadata.pop('SUSignedFeedFailureExpirationInterval')
                else:
                    metadata['SUSignedFeedFailureExpirationInterval'] = value
                with self.assertRaisesRegex(ValueError, 'SUSignedFeedFailureExpirationInterval'):
                    policy.validate_info(metadata)

    def test_policy_cli_commands_run_as_real_subprocesses(self):
        scripts = self.root / 'scripts/release'
        scripts.mkdir(parents=True)
        shutil.copy(Path(policy.__file__), scripts / 'policy.py')
        (self.root / 'CHANGELOG.md').write_text('## [1.2.3]\n\n- Test release.\n')
        for command in ('version', 'names', 'notes', 'info', 'shell'):
            with self.subTest(command=command):
                result = subprocess.run([sys.executable, str(scripts / 'policy.py'), command],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                if command == 'shell':
                    self.assertIn('POOKIE_ARCH=arm64', result.stdout)

    def test_config_fails_immediately_when_policy_command_fails(self):
        scripts = self.root / 'scripts/release'
        scripts.mkdir(parents=True)
        shutil.copy(Path(policy.__file__).with_name('config.sh'), scripts / 'config.sh')
        (scripts / 'policy.py').write_text('raise SystemExit(42)\n')
        result = subprocess.run(['bash', '-e', '-c',
                                 'source "$1"; echo POLICY_FAILURE_WAS_MASKED',
                                 'config-test', str(scripts / 'config.sh')],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('POLICY_FAILURE_WAS_MASKED', result.stdout)

    def test_current_versioned_main_commit_is_releasable(self):
        self.source()
        policy.validate_source(self.root, 'refs/tags/v1.2.3')

    def test_ref_must_match_source_version(self):
        self.source()
        with self.assertRaisesRegex(ValueError, 'ref'):
            policy.validate_source(self.root, 'refs/tags/v9.9.9')

    def test_tag_must_point_to_checked_out_source(self):
        self.source()
        self.git('commit', '--allow-empty', '-m', 'new source')
        with self.assertRaisesRegex(ValueError, 'tag'):
            policy.validate_source(self.root, 'refs/tags/v1.2.3')

    def test_release_must_belong_to_main(self):
        self.source()
        self.git('commit', '--allow-empty', '-m', 'off main')
        self.git('tag', '-f', 'v1.2.3')
        with self.assertRaisesRegex(ValueError, 'main'):
            policy.validate_source(self.root, 'refs/tags/v1.2.3')

    def test_dirty_source_is_rejected(self):
        self.source()
        (self.root / 'untracked').write_text('not in tag')
        with self.assertRaisesRegex(ValueError, 'dirty'):
            policy.validate_source(self.root, 'refs/tags/v1.2.3')

    def test_old_build_and_version_are_rejected(self):
        self.source()
        self.git('tag', 'v1.2.2')
        with self.assertRaisesRegex(ValueError, 'increase'):
            policy.validate_source(self.root, 'refs/tags/v1.2.3')

    def test_missing_changelog_entry_is_rejected(self):
        self.source()
        (self.root / 'CHANGELOG.md').write_text('## [0.0.1]\n- Other release.\n')
        with self.assertRaisesRegex(ValueError, 'changelog'):
            policy.release_notes(self.root, '1.2.3')

    def test_mismatched_bundle_metadata_is_rejected(self):
        altered = self.metadata | {'PookieChannel': 'development'}
        with self.assertRaisesRegex(ValueError, 'PookieChannel'):
            policy.validate_bundle_info(altered, self.metadata)

    def test_placeholder_key_and_wrong_feed_are_rejected(self):
        for key, value in [('SUPublicEDKey', 'SET_ME'), ('SUFeedURL', 'https://evil.invalid/feed')]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                policy.validate_info(self.metadata | {key: value})

    def test_signed_feed_and_early_verification_cannot_be_disabled(self):
        for key in ('SURequireSignedFeed', 'SUVerifyUpdateBeforeExtraction'):
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, key):
                policy.validate_info(self.metadata | {key: False})

    def test_signed_feed_metadata_matches_source(self):
        policy.validate_feed(self.feed(), self.metadata, self.root)

    def test_tampered_feed_version_url_length_and_signature_are_rejected(self):
        for old, new in [('>12<', '>13<'), ('github.com/antick', 'evil.invalid/antick'),
                         ('length="', 'length="999'), ('sparkle:edSignature="', 'sparkle:edSignature="!')]:
            with self.subTest(old=old):
                feed = self.feed()
                feed.write_text(feed.read_text().replace(old, new))
                with self.assertRaises(ValueError):
                    policy.validate_feed(feed, self.metadata, self.root)

    def test_duplicate_feed_fields_are_rejected(self):
        path = self.feed()
        path.write_text(path.read_text().replace('<sparkle:version>12</sparkle:version>',
                        '<sparkle:version>12</sparkle:version><sparkle:version>99</sparkle:version>'))
        with self.assertRaisesRegex(ValueError, 'version'):
            policy.validate_feed(path, self.metadata, self.root)

    def test_corresponding_source_must_be_the_exact_tagged_tree(self):
        self.assertTrue(hasattr(policy, 'verify_source_archive'), 'Exact source archive validation is missing')
        self.source()
        path = self.root / 'source.tar.gz'
        data = subprocess.check_output(['git', '-C', str(self.root), 'archive', '--format=tar.gz',
                                        '--prefix=Pookie-1.2.3/', 'v1.2.3'])
        path.write_bytes(data)
        policy.verify_source_archive(path, self.root, '1.2.3')
        path.write_bytes(data + b'altered source')
        with self.assertRaisesRegex(ValueError, 'tagged source'):
            policy.verify_source_archive(path, self.root, '1.2.3')

    def test_complete_assets_pass(self):
        self.assets()
        policy.validate_assets(self.root, self.metadata)

    def test_missing_asset_and_tampered_archive_are_rejected(self):
        self.assets()
        archive = self.root / 'Pookie-1.2.3-arm64.zip'
        archive.write_bytes(archive.read_bytes() + b'tampered')
        with self.assertRaisesRegex(ValueError, 'checksum'):
            policy.validate_assets(self.root, self.metadata)
        self.assets()
        (self.root / 'Pookie-1.2.3-arm64.dmg').unlink()
        with self.assertRaisesRegex(ValueError, 'Missing'):
            policy.validate_assets(self.root, self.metadata)

    def test_archive_metadata_must_match_even_with_updated_checksum(self):
        self.assets()
        with zipfile.ZipFile(self.root / 'Pookie-1.2.3-arm64.zip', 'w') as archive:
            archive.writestr('Pookie.app/Contents/Info.plist',
                             plistlib.dumps(self.metadata | {'CFBundleVersion': '99'}))
        self.checksums()
        with self.assertRaisesRegex(ValueError, 'CFBundleVersion'):
            policy.validate_assets(self.root, self.metadata)


if __name__ == '__main__':
    unittest.main()
