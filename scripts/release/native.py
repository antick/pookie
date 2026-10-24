#!/usr/bin/env python3
"""Inspect, thin, then sign every nested Mach-O from the inside out."""
from pathlib import Path
import plistlib
import subprocess
import sys

from policy import ARCH, BUNDLE_ID, TEAM_ID, source_info, validate_bundle_info, validate_info


def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()


def binaries(app):
    found = []
    for path in app.rglob('*'):
        if path.is_symlink():
            if not path.resolve().is_relative_to(app.resolve()):
                raise ValueError(f'Bundle symlink escapes app: {path}')
            continue
        if path.is_file() and 'Mach-O' in run('file', '-b', str(path)):
            found.append(path)
    if not found:
        raise ValueError('No native code in bundle')
    return found


def verify_architectures(app):
    found = binaries(app)
    for path in found:
        arch = run('lipo', '-archs', str(path))
        if arch != ARCH:
            raise ValueError(f'Unexpected architecture {arch}: {path}')
    return len(found)


def developer_requirement(identifier=None):
    requirement = ('anchor apple generic and certificate leaf[subject.OU] = "' + TEAM_ID + '" '
                   'and certificate leaf[field.1.2.840.113635.100.6.1.13] exists')
    if identifier:
        requirement += ' and identifier "' + identifier + '"'
    return '=' + requirement


def sign_bundle(app, identity, production):
    if production and (not identity or identity == '-'):
        raise ValueError('Production requires Developer ID signing')
    found = binaries(app)
    # Finish architecture work before the first signature: thinning invalidates signatures.
    for path in found:
        arch = run('lipo', '-archs', str(path)).split()
        if ARCH not in arch:
            raise ValueError(f'No Apple silicon slice: {path}')
        if arch != [ARCH]:
            temporary = path.with_name(path.name + '.arm64')
            try:
                run('lipo', str(path), '-thin', ARCH, '-output', str(temporary))
                temporary.chmod(path.stat().st_mode)
                temporary.replace(path)
            finally:
                temporary.unlink(missing_ok=True)
    bundles = [p for p in app.rglob('*') if p.is_dir() and not p.is_symlink()
               and p.suffix in ('.app', '.xpc', '.framework', '.bundle')]
    nested = sorted(set(found + bundles), key=lambda p: (len(p.parts), str(p)), reverse=True)
    for path in nested + [app]:
        args = ['codesign', '--force', '--sign', identity]
        args += ['--timestamp', '--options', 'runtime'] if production else ['--timestamp=none']
        run(*args, str(path))
    run('codesign', '--verify', '--deep', '--strict', str(app))
    verify_architectures(app)
    if production:
        verify_signatures(app)


def verify_signatures(app):
    for path in binaries(app):
        run('codesign', '--verify', '--strict', '-R', developer_requirement(), str(path))
        details = run('codesign', '-d', '--verbose=4', str(path))
        if 'runtime' not in details or 'Timestamp=' not in details:
            raise ValueError(f'Missing hardened runtime or secure timestamp: {path}')
    run('codesign', '--verify', '--deep', '--strict', '-R', developer_requirement(BUNDLE_ID), str(app))


def verify_bundle(app):
    source = source_info()
    validate_info(source)
    metadata = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    validate_bundle_info(metadata, source)
    for name in ('LICENSE', 'THIRD_PARTY_NOTICES.md', 'Sparkle-LICENSE.txt'):
        if not (app / 'Contents/Resources' / name).is_file():
            raise ValueError('Missing bundled notice: ' + name)
    executable = app / 'Contents/MacOS/Pookie'
    if '@executable_path/../Frameworks' not in run('otool', '-l', str(executable)):
        raise ValueError('Missing bundle-relative framework rpath')
    if '@rpath/Sparkle.framework/' not in run('otool', '-L', str(executable)):
        raise ValueError('Missing embedded Sparkle linkage')
    count = verify_architectures(app)
    verify_signatures(app)
    run('xcrun', 'stapler', 'validate', str(app))
    run('spctl', '--assess', '--type', 'execute', '--verbose=4', str(app))
    print(f'Verified signed, notarized app and {count} arm64-only binaries.')


if __name__ == '__main__':
    try:
        command, app = sys.argv[1], Path(sys.argv[2]).resolve()
        if command == 'sign':
            sign_bundle(app, sys.argv[3], production=sys.argv[4] == 'production')
        elif command == 'verify':
            verify_bundle(app)
        elif command == 'architectures':
            print(f'Verified {verify_architectures(app)} arm64-only binaries.')
        else:
            raise ValueError('Unknown native release command')
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
