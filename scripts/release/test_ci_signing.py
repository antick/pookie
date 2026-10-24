"""Credential lifecycle tests never invoke macOS security or touch real secrets."""
import base64
import json
from pathlib import Path
import tempfile
import unittest

try:
    import ci_signing
except ImportError:
    ci_signing = None


class TemporarySigningTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(ci_signing, 'Temporary signing lifecycle is missing')
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.calls = []
        self.env = dict(MAC_CERTIFICATE=base64.b64encode(b'fixture certificate').decode(),
                        MAC_CERTIFICATE_PASSWORD='fixture password', APPLE_API_KEY_P8='fixture api key',
                        APPLE_API_KEY_ID='ABC1234567', APPLE_API_ISSUER='fixture issuer',
                        SPARKLE_PRIVATE_KEY=base64.b64encode(bytes(range(32))).decode(),
                        RUNNER_TEMP=str(self.directory), GITHUB_ENV=str(self.directory / 'env'))

    def command(self, *args):
        self.calls.append(args)
        if args[:2] == ('security', 'list-keychains') and '-s' not in args:
            return '    "/fixture/login.keychain-db"\n    "/fixture/another keychain-db"'
        if args[:2] == ('security', 'create-keychain'):
            Path(args[-1]).touch()
        if args[:2] == ('security', 'find-identity'):
            return '1) ' + 'A' * 40 + ' "Developer ID Application: Fixture (2L85KT5GNL)"'
        return ''

    def test_prepare_preserves_search_list_and_cleanup_restores_it(self):
        ci_signing.prepare(self.env, self.command)
        state = self.directory / 'pookie-signing'
        self.assertEqual(json.loads((state / 'search-list.json').read_text()),
                         ['/fixture/login.keychain-db', '/fixture/another keychain-db'])
        exported = (self.directory / 'env').read_text()
        self.assertIn('POOKIE_SIGN_IDENTITY=' + 'A' * 40, exported)
        self.assertIn('NOTARY_PROFILE=pookie-notary', exported)
        self.assertNotIn('fixture password', exported)
        self.assertNotIn(self.env['SPARKLE_PRIVATE_KEY'], exported)
        self.assertFalse((state / 'certificate.p12').exists())
        self.assertFalse((state / 'AuthKey.p8').exists())
        self.assertEqual((state / 'sparkle-key').stat().st_mode & 0o777, 0o600)
        ci_signing.cleanup(self.env, self.command)
        self.assertIn(('security', 'list-keychains', '-d', 'user', '-s',
                       '/fixture/login.keychain-db', '/fixture/another keychain-db'), self.calls)
        self.assertFalse(state.exists())

    def test_missing_secret_changes_nothing(self):
        del self.env['SPARKLE_PRIVATE_KEY']
        with self.assertRaisesRegex(ValueError, 'SPARKLE_PRIVATE_KEY'):
            ci_signing.prepare(self.env, self.command)
        self.assertFalse(self.calls)
        self.assertFalse((self.directory / 'pookie-signing').exists())

    def test_failure_after_import_cleans_material_and_restores_search_list(self):
        def fail(*args):
            result = self.command(*args)
            if args[:2] == ('security', 'import') and 'certificate.p12' in args[2]:
                raise ValueError('simulated failed import')
            return result
        with self.assertRaisesRegex(ValueError, 'simulated'):
            ci_signing.prepare(self.env, fail)
        self.assertFalse((self.directory / 'pookie-signing').exists())
        self.assertTrue(any(call[:2] == ('security', 'delete-keychain') for call in self.calls))

    def test_existing_signing_directory_is_never_overwritten(self):
        (self.directory / 'pookie-signing').mkdir()
        with self.assertRaisesRegex(ValueError, 'exists'):
            ci_signing.prepare(self.env, self.command)
        self.assertFalse(self.calls)


if __name__ == '__main__':
    unittest.main()
