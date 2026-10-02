"""Restore the existing upload key without logging secret values."""
import base64
import os
from pathlib import Path


def property_value(value):
    return value.replace('\\', '\\\\').replace('\n', '\\n').replace('\r', '\\r').replace(' ', '\\ ').replace('=', '\\=').replace(':', '\\:')


def main():
    names = ['ANDROID_KEYSTORE_BASE64', 'ANDROID_KEYSTORE_PASSWORD', 'ANDROID_KEY_ALIAS', 'ANDROID_KEY_PASSWORD']
    missing = [name for name in names if not os.environ.get(name)]
    if missing:
        raise SystemExit('Missing signing secrets: ' + ', '.join(missing))
    key = Path('android/app/upload-keystore.jks')
    key.write_bytes(base64.b64decode(os.environ[names[0]], validate=True))
    key.chmod(0o600)
    values = {'storeFile': 'upload-keystore.jks', 'storePassword': os.environ[names[1]], 'keyAlias': os.environ[names[2]], 'keyPassword': os.environ[names[3]]}
    properties = Path('android/key.properties')
    properties.write_text(''.join(f'{k}={property_value(v)}\n' for k, v in values.items()))
    properties.chmod(0o600)


if __name__ == '__main__':
    main()
