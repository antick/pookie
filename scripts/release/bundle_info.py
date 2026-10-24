#!/usr/bin/env python3
"""Change identity, never version/build, when assembling a development bundle."""
from pathlib import Path
import plistlib
import sys

from policy import source_info, validate_info


def for_channel(source, channel):
    metadata = dict(source)
    if channel == 'production':
        validate_info(source)
    elif channel == 'development':
        metadata = {key: value for key, value in metadata.items() if not key.startswith('SU')}
        metadata.update(CFBundleIdentifier='com.pookie.pet.dev', CFBundleName='Pookie Dev',
                        CFBundleDisplayName='Pookie Dev', PookieChannel='development',
                        SUEnableAutomaticChecks=False, SUAutomaticallyUpdate=False)
    else:
        raise ValueError('Expected development or production channel')
    metadata['CFBundleIconFile'] = 'AppIcon'
    return metadata


if __name__ == '__main__':
    destination, channel = sys.argv[1:]
    Path(destination).write_bytes(plistlib.dumps(for_channel(source_info(), channel)))
