#!/usr/bin/env python3
"""CI credential lifecycle. Subprocess diagnostics with secrets are never logged."""
import base64
import json
import os
from pathlib import Path
import re
import secrets
import shlex
import shutil
import subprocess
import sys

from policy import NOTARY_PROFILE, ROOT, TEAM_ID

REQUIRED = ('MAC_CERTIFICATE', 'MAC_CERTIFICATE_PASSWORD', 'APPLE_API_KEY_P8',
            'APPLE_API_KEY_ID', 'APPLE_API_ISSUER', 'SPARKLE_PRIVATE_KEY', 'RUNNER_TEMP', 'GITHUB_ENV')


def secret_run(*args):
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode:
        raise ValueError(f'{args[0]} {args[1]} failed; secret-bearing output withheld')
    return result.stdout.strip()


def cleanup(env, run=secret_run):
    directory = Path(env['RUNNER_TEMP']) / 'pookie-signing'
    state = directory / 'search-list.json'
    keychain = directory / 'release.keychain-db'
    try:
        if state.exists():
            run('security', 'list-keychains', '-d', 'user', '-s', *json.loads(state.read_text()))
    finally:
        try:
            if keychain.exists():
                run('security', 'delete-keychain', str(keychain))
        finally:
            if directory.exists():
                shutil.rmtree(directory)


def prepare(env, run=secret_run):
    missing = [name for name in REQUIRED if not env.get(name)]
    if missing:
        raise ValueError('Missing required release secrets: ' + ', '.join(missing))
    directory = Path(env['RUNNER_TEMP']) / 'pookie-signing'
    if directory.exists():
        raise ValueError('Temporary signing directory already exists; clean it first')
    certificate_data = base64.b64decode(env['MAC_CERTIFICATE'], validate=True)
    update_data = base64.b64decode(env['SPARKLE_PRIVATE_KEY'].strip(), validate=True)
    if len(update_data) not in (32, 96):
        raise ValueError('Invalid exported Sparkle private key length')
    previous = shlex.split(run('security', 'list-keychains', '-d', 'user'))
    directory.mkdir(mode=0o700)
    try:
        (directory / 'search-list.json').write_text(json.dumps(previous))
        keychain = str(directory / 'release.keychain-db')
        password = secrets.token_hex(32)
        certificate = directory / 'certificate.p12'
        api_key = directory / 'AuthKey.p8'
        update_key = directory / 'sparkle-key'
        for path, data in ((certificate, certificate_data),
                           (api_key, env['APPLE_API_KEY_P8'].encode()),
                           (update_key, env['SPARKLE_PRIVATE_KEY'].strip().encode())):
            descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(descriptor, 'wb') as output:
                output.write(data)
        run('security', 'create-keychain', '-p', password, keychain)
        run('security', 'set-keychain-settings', '-lut', '21600', keychain)
        run('security', 'unlock-keychain', '-p', password, keychain)
        run('security', 'list-keychains', '-d', 'user', '-s', keychain, *previous)
        # Public Apple intermediate; avoids relying on runner-specific certificate caches.
        run('security', 'import', str(ROOT / 'scripts/release/DeveloperIDG2CA.cer'), '-k', keychain)
        run('security', 'import', str(certificate), '-k', keychain, '-P',
            env['MAC_CERTIFICATE_PASSWORD'], '-T', '/usr/bin/codesign', '-T', '/usr/bin/security')
        run('security', 'set-key-partition-list', '-S', 'apple-tool:,apple:', '-s', '-k', password, keychain)
        certificate.unlink()
        identities = run('security', 'find-identity', '-v', '-p', 'codesigning', keychain)
        matches = re.findall(r'\b([A-Fa-f0-9]{40})\s+"Developer ID Application:[^\n]+\('
                             + re.escape(TEAM_ID) + r'\)"', identities)
        if len(set(matches)) != 1:
            raise ValueError('Expected one Developer ID Application identity for the configured team')
        run('xcrun', 'notarytool', 'store-credentials', NOTARY_PROFILE, '--keychain', keychain,
            '--key', str(api_key), '--key-id', env['APPLE_API_KEY_ID'], '--issuer', env['APPLE_API_ISSUER'])
        api_key.unlink()
        with open(env['GITHUB_ENV'], 'a') as output:
            output.write(f'POOKIE_SIGN_IDENTITY={matches[0]}\nNOTARY_PROFILE={NOTARY_PROFILE}\n')
            output.write(f'NOTARY_KEYCHAIN={keychain}\nSPARKLE_KEY_FILE={update_key}\n')
    except BaseException:
        cleanup(env, run)
        raise
    print('Temporary signing keychain and notarization profile are ready.')


if __name__ == '__main__':
    try:
        if sys.argv[1] == 'prepare':
            prepare(os.environ)
        elif sys.argv[1] == 'cleanup':
            cleanup(os.environ)
        else:
            raise ValueError('Expected prepare or cleanup')
    except (ValueError, OSError) as error:
        raise SystemExit(str(error))
