#!/usr/bin/env python3
"""Shared release constants and validation; standard library only."""
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import subprocess
import sys
import tarfile
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[2]
PLIST = 'Resources/Info.plist'
ARCH = 'arm64'
TEAM_ID = '2L85KT5GNL'
REPOSITORY = 'antick/pookie'
SPARKLE_VERSION = '2.10.0'
FEED_URL = 'https://antick.github.io/pookie/appcast.xml'
BUNDLE_ID = 'com.pookie.pet'
MINIMUM_OS = '14.0'
NOTARY_PROFILE = 'pookie-notary'
SPARKLE_ACCOUNT = 'pookie'
SPARKLE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
BUNDLE_KEYS = ('CFBundleIdentifier', 'CFBundleExecutable', 'CFBundleVersion',
               'CFBundleShortVersionString', 'LSMinimumSystemVersion',
               'PookieChannel', 'SUPublicEDKey', 'SUFeedURL', 'SUSignedFeedFailureExpirationInterval',
               'SURequireSignedFeed', 'SUVerifyUpdateBeforeExtraction')
SOURCE_FILES = ('README.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md', 'Package.swift',
                'Package.resolved', 'Makefile', 'scripts/bundle.sh', PLIST)


def source_info(root=ROOT):
    return plistlib.loads((root / PLIST).read_bytes())


def version_tuple(version):
    if not isinstance(version, str) or not re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)', version):
        raise ValueError('Release requires a three-part semantic version')
    return tuple(map(int, version.split('.')))


def validate_info(info):
    version_tuple(info.get('CFBundleShortVersionString'))
    build = info.get('CFBundleVersion', '')
    if not isinstance(build, str) or not re.fullmatch(r'[1-9]\d*', build):
        raise ValueError('Release requires a positive numeric build')
    expected = dict(CFBundleIdentifier=BUNDLE_ID, CFBundleExecutable='Pookie',
                    PookieChannel='production', LSMinimumSystemVersion=MINIMUM_OS,
                    SUFeedURL=FEED_URL, SURequireSignedFeed=True,
                    SUVerifyUpdateBeforeExtraction=True)
    for key, value in expected.items():
        if info.get(key) != value:
            raise ValueError(f'Unexpected source {key}')
    expiration = info.get('SUSignedFeedFailureExpirationInterval')
    if type(expiration) not in (int, float) or expiration != 0:
        raise ValueError('Unexpected source SUSignedFeedFailureExpirationInterval')
    try:
        key = base64.b64decode(info.get('SUPublicEDKey', ''), validate=True)
    except (ValueError, TypeError) as error:
        raise ValueError('Invalid Sparkle public key') from error
    if len(key) != 32 or len(set(key)) < 2:
        raise ValueError('Missing Sparkle public key')


def validate_bundle_info(info, source):
    for key in BUNDLE_KEYS:
        if key not in source or info.get(key) != source[key]:
            raise ValueError(f'Packaged {key} does not match release source')


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()


def release_notes(root, version):
    path = root / 'CHANGELOG.md'
    if not path.is_file():
        raise ValueError('Missing release changelog')
    sections = re.split(r'^## +', path.read_text(), flags=re.MULTILINE)[1:]
    for section in sections:
        heading, _, body = section.partition('\n')
        if re.match(r'\[?' + re.escape(version) + r'\]?(?:\s|$)', heading) and body.strip():
            return body.strip() + '\n'
    raise ValueError('Missing current version in changelog')


def validate_source(root, ref):
    info = source_info(root)
    validate_info(info)
    version, build = info['CFBundleShortVersionString'], int(info['CFBundleVersion'])
    if ref != 'refs/tags/v' + version:
        raise ValueError('Release ref must match Info.plist version')
    if git(root, 'status', '--porcelain', '--untracked-files=all'):
        raise ValueError('Release source is dirty')
    tag = 'v' + version
    if git(root, 'rev-parse', 'HEAD') != git(root, 'rev-parse', tag + '^{commit}'):
        raise ValueError('Release tag does not match checked-out source')
    if subprocess.run(['git', '-C', str(root), 'merge-base', '--is-ancestor',
                       'HEAD', 'origin/main'], capture_output=True).returncode:
        raise ValueError('Release commit must belong to origin/main')
    for previous in git(root, 'tag', '--list', 'v*').splitlines():
        if previous == tag or not re.fullmatch(r'v\d+\.\d+\.\d+', previous):
            continue
        old = subprocess.run(['git', '-C', str(root), 'show', f'{previous}:{PLIST}'],
                             capture_output=True, check=True)
        metadata = plistlib.loads(old.stdout)
        if version_tuple(metadata['CFBundleShortVersionString']) >= version_tuple(version):
            raise ValueError('Version must increase beyond previous releases')
        if int(metadata['CFBundleVersion']) >= build:
            raise ValueError('Build must increase beyond previous releases')
    package = (root / 'Package.swift').read_text()
    if not re.search(r'\.package\(\s*url:\s*"https://github.com/sparkle-project/Sparkle(?:\.git)?"\s*,\s*exact:\s*"'
                     + re.escape(SPARKLE_VERSION) + r'"\s*\)', package):
        raise ValueError('Package.swift must pin Sparkle exactly')
    pins = json.loads((root / 'Package.resolved').read_text())['pins']
    sparkle = [pin for pin in pins if pin['identity'].lower() == 'sparkle']
    if len(sparkle) != 1 or sparkle[0]['state'].get('version') != SPARKLE_VERSION:
        raise ValueError('Sparkle lockfile does not match approved version')
    release_notes(root, version)


def asset_names(info):
    stem = 'Pookie-' + info['CFBundleShortVersionString']
    return (stem + '-arm64.dmg', stem + '-arm64.zip', stem + '-source.tar.gz',
            'appcast.xml', 'SHA256SUMS')


def validate_feed(path, info, artifacts):
    items = ET.parse(path).findall('./channel/item')
    if len(items) != 1:
        raise ValueError('Expected exactly one current release in feed')
    item = items[0]
    for element, key in [('version', 'CFBundleVersion'),
                         ('shortVersionString', 'CFBundleShortVersionString'),
                         ('minimumSystemVersion', 'LSMinimumSystemVersion')]:
        values = item.findall(SPARKLE + element)
        if len(values) != 1 or values[0].text != info[key]:
            raise ValueError(f'Feed {element} does not match source')
    enclosures = item.findall('enclosure')
    if len(enclosures) != 1:
        raise ValueError('Expected one archive enclosure')
    enclosure = enclosures[0]
    version = info['CFBundleShortVersionString']
    name = f'Pookie-{version}-arm64.zip'
    url = f'https://github.com/{REPOSITORY}/releases/download/v{version}/{name}'
    if enclosure is None or enclosure.get('url') != url:
        raise ValueError('Unexpected download URL')
    if int(enclosure.get('length', '0')) != (artifacts / name).stat().st_size:
        raise ValueError('Archive size mismatch')
    try:
        signature = base64.b64decode(enclosure.get(SPARKLE + 'edSignature', ''), validate=True)
    except (ValueError, TypeError) as error:
        raise ValueError('Invalid archive signature') from error
    if len(signature) != 64:
        raise ValueError('Missing archive signature')


def verify_source_archive(path, root, version):
    process = subprocess.Popen(['git', '-C', str(root), 'archive', '--format=tar.gz',
                                '--prefix=Pookie-' + version + '/', 'v' + version],
                               stdout=subprocess.PIPE)
    digest = hashlib.sha256()
    try:
        for chunk in iter(lambda: process.stdout.read(1024 * 1024), b''):
            digest.update(chunk)
    finally:
        process.stdout.close()
        status = process.wait()
    if status or hashlib.sha256(path.read_bytes()).digest() != digest.digest():
        raise ValueError('Archive does not match exact tagged source')


def validate_assets(artifacts, info, source_root=None):
    names = asset_names(info)
    for name in names:
        if not (artifacts / name).is_file() or (artifacts / name).stat().st_size == 0:
            raise ValueError('Missing release asset: ' + name)
    expected = {}
    for line in (artifacts / 'SHA256SUMS').read_text().splitlines():
        match = re.fullmatch(r'([a-f0-9]{64})  ([^/]+)', line)
        if not match or match[2] in expected:
            raise ValueError('Invalid checksum manifest')
        expected[match[2]] = match[1]
    if set(expected) != set(names) - {'SHA256SUMS'}:
        raise ValueError('Incomplete checksum manifest')
    for name, digest in expected.items():
        if hashlib.sha256((artifacts / name).read_bytes()).hexdigest() != digest:
            raise ValueError('Release checksum mismatch: ' + name)
    with zipfile.ZipFile(artifacts / names[1]) as archive:
        metadata = plistlib.loads(archive.read('Pookie.app/Contents/Info.plist'))
        validate_bundle_info(metadata, info)
    with tarfile.open(artifacts / names[2], 'r:gz') as archive:
        prefix = 'Pookie-' + info['CFBundleShortVersionString'] + '/'
        for name in SOURCE_FILES:
            member = archive.getmember(prefix + name)
            if not member.isfile():
                raise ValueError('Missing corresponding source: ' + name)
        metadata = plistlib.loads(archive.extractfile(prefix + PLIST).read())
        validate_bundle_info(metadata, info)
    validate_feed(artifacts / 'appcast.xml', info, artifacts)
    if source_root is not None:
        verify_source_archive(artifacts / names[2], source_root, info['CFBundleShortVersionString'])


def main():
    command = sys.argv[1]
    info = source_info()
    artifacts = ROOT / 'build/release-artifacts'
    if command == 'version':
        print(info['CFBundleShortVersionString'])
    elif command == 'names':
        print('\n'.join(asset_names(info)))
    elif command == 'notes':
        print(release_notes(ROOT, info['CFBundleShortVersionString']), end='')
    elif command == 'source':
        validate_source(ROOT, os.environ.get('GITHUB_REF', 'refs/tags/v' + info['CFBundleShortVersionString']))
    elif command == 'info':
        validate_info(info)
    elif command == 'feed':
        validate_feed(artifacts / 'appcast.xml', info, artifacts)
    elif command == 'assets':
        validate_assets(artifacts, info, ROOT)
    elif command == 'checksums':
        with (artifacts / 'SHA256SUMS').open('w') as output:
            for name in asset_names(info):
                if name != 'SHA256SUMS':
                    digest = hashlib.sha256((artifacts / name).read_bytes()).hexdigest()
                    output.write(f'{digest}  {name}\n')
    elif command == 'shell':
        values = dict(POOKIE_PLIST=ROOT / PLIST, POOKIE_ARCH=ARCH, POOKIE_TEAM_ID=TEAM_ID,
                      POOKIE_REPOSITORY=REPOSITORY, POOKIE_SPARKLE_VERSION=SPARKLE_VERSION,
                      POOKIE_ARTIFACTS=artifacts, POOKIE_NOTARY_PROFILE=NOTARY_PROFILE,
                      POOKIE_SPARKLE_ACCOUNT=SPARKLE_ACCOUNT,
                      POOKIE_SPARKLE_BIN=ROOT / '.build/artifacts/sparkle/Sparkle/bin',
                      POOKIE_SPARKLE_FRAMEWORK=ROOT / ('.build/artifacts/sparkle/Sparkle/'
                          'Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework'))
        for name, value in values.items():
            print(name + '=' + shlex.quote(str(value)))
    else:
        raise ValueError('Unknown policy command')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
