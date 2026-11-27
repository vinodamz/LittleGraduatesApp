"""Upload a signed bundle or promote one tested version through Google Play edits."""
import argparse
import json
import os
from pathlib import Path

PACKAGE = 'in.thelittlegraduates.app'
BASE = f'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACKAGE}/edits'
APPLICATION = BASE.removesuffix('/edits')


def version_code(value):
    if not value.isdecimal() or not 0 < int(value) <= 2100000000:
        raise argparse.ArgumentTypeError('Version code must be a positive Android integer')
    return str(int(value))


def inspect_tracks(session):
    """Read actual review/publication states without opening or committing an edit."""
    tracks = {}
    for track in ['internal', 'production']:
        response = session.request('GET', f'{APPLICATION}/tracks/{track}/releases', timeout=60)
        response.raise_for_status()
        tracks[track] = response.json().get('releases', [])
    return {'package': PACKAGE, 'tracks': tracks}


def release(session, mode, code, bundle=None):
    def request(method, url, **kwargs):
        response = session.request(method, url, timeout=300, **kwargs)
        status = getattr(response, 'status_code', None)
        if status is not None and status >= 400:
            print(f'Play API HTTP {status} body: {getattr(response, "text", "")}')
        response.raise_for_status()
        return response.json() if response.content else {}

    edit = request('POST', BASE, json={})['id']
    url = f'{BASE}/{edit}'
    try:
        if mode == 'upload':
            with Path(bundle).open('rb') as source:
                uploaded = request('POST', url.replace('googleapis.com/', 'googleapis.com/upload/') + '/bundles?uploadType=media', data=source, headers={'Content-Type': 'application/octet-stream'})
            if str(uploaded['versionCode']) != code:
                raise ValueError('Bundle version code does not match requested version')
            track = 'internal'
        else:
            internal = request('GET', url + '/tracks/internal')
            tested = any(code in map(str, r.get('versionCodes', [])) and r.get('status') == 'completed' for r in internal.get('releases', []))
            if not tested:
                raise ValueError('Version is not an active completed internal testing release')
            track = 'production'
        request('PUT', url + '/tracks/' + track, json={'track': track, 'releases': [{'versionCodes': [code], 'status': 'completed'}]})
        request('POST', url + ':validate', json={})
        request('POST', url + ':commit', json={})
        print(f'Google Play {track} release committed: version code {code}')
    except Exception:
        try:
            session.request('DELETE', url, timeout=30)
        except Exception:
            pass
        raise


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=['upload', 'promote', 'status'])
    parser.add_argument('--version-code', type=version_code)
    parser.add_argument('--bundle')
    parser.add_argument('--output', help='Save non-secret release status as JSON')
    args = parser.parse_args()
    if args.mode != 'status' and not args.version_code:
        parser.error('--version-code is required for upload or promote')
    if args.mode == 'upload' and not args.bundle:
        parser.error('--bundle is required for upload')
    raw = os.environ.get('PLAY_SERVICE_ACCOUNT_JSON')
    if not raw:
        raise SystemExit('Missing PLAY_SERVICE_ACCOUNT_JSON secret')
    from google.oauth2 import service_account
    from google.auth.transport.requests import AuthorizedSession
    credentials = service_account.Credentials.from_service_account_info(json.loads(raw), scopes=['https://www.googleapis.com/auth/androidpublisher'])
    with AuthorizedSession(credentials) as session:
        if args.mode == 'status':
            status = inspect_tracks(session)
            rendered = json.dumps(status, indent=2)
            if args.output:
                Path(args.output).write_text(rendered + '\n')
            print(rendered)
            return
        release(session, args.mode, args.version_code, args.bundle)


if __name__ == '__main__':
    main()
