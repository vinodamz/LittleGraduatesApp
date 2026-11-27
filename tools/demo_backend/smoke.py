"""Exercise real login -> mark -> multipart upload -> authenticated byte readback.

Only a loopback demo backend with the explicit /demo/health marker is accepted.
Does not save API tokens or print response bodies. Generated data is synthetic.
"""
import argparse
import hashlib
import json
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('runtime', type=Path)
    parser.add_argument('--base-url', default='http://127.0.0.1:8765')
    args = parser.parse_args()
    root = args.runtime.resolve()
    if (root / '.demo-only').read_text() != 'LG_ANDROID_DEMO\n':
        raise SystemExit('Not a demo runtime')
    base = args.base_url.rstrip('/')
    parsed = urllib.parse.urlsplit(base)
    if parsed.scheme != 'http' or parsed.hostname not in ('127.0.0.1', 'localhost', '::1') or parsed.path or parsed.username or parsed.password:
        raise SystemExit('Only a loopback HTTP demo origin is permitted')
    fixture = json.loads((root / 'fixture.json').read_text())
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            raise AssertionError('Demo APIs must never redirect')

    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    token = None

    def request(path, data=None, content_type=None, authenticate=True, host=None):
        if not path.startswith('/') or path.startswith('//'):
            raise AssertionError('Not a local API path')
        headers = {}
        if host:
            headers['Host'] = host
        if content_type:
            headers['Content-Type'] = content_type
        if authenticate and token:
            headers['Authorization'] = 'Bearer ' + token
        req = urllib.request.Request(base + path, data=data, headers=headers)
        try:
            with opener.open(req, timeout=150) as response:
                assert urllib.parse.urlsplit(response.url).netloc == parsed.netloc, 'Redirect left demo origin'
                return response.status, response.read()
        except urllib.error.HTTPError as error:
            return error.code, error.read()

    def api(path, data=None):
        status, raw = request('/api/v1/' + path,
                              json.dumps(data).encode() if data is not None else None,
                              'application/json' if data is not None else None)
        result = json.loads(raw)
        assert status == 200 and result.get('ok') is True, f'API failed: {path}, HTTP {status}'
        return result

    status, body = request('/demo/health', authenticate=False)
    health = json.loads(body)
    assert status == 200 and health.get('demo_only') is True
    assert health['mtt_commit'] == fixture['mtt_commit']
    users = api('login_users.php')['users']
    user = next(u for u in users if u['name'] == 'Demo Materials Teacher')
    assert user['id'] == fixture['user']['id']
    login = api('login.php', {'user_id': user['id'], 'pin': fixture['user']['pin'], 'device_name': 'Synthetic backend smoke'})
    token = login['token']
    assert api('me.php')['user']['id'] == user['id']
    sheet = api('materials/today.php')['day']
    material = next(m for m in sheet['materials'] if m['name'] == 'Demo Number Rods')
    assert material['location'] == 'Demo shelf'
    date = sheet['date']
    api('materials/mark.php', {'material_id': material['id'], 'date': date, 'condition_code': 'good', 'notes': 'Synthetic demo attachment'})
    prior_ids = {m['id'] for m in material['media']}
    client_key = 'demo-smoke-' + uuid.uuid4().hex
    boundary = 'LGDemo' + uuid.uuid4().hex
    image = (root / 'demo-material.png').read_bytes()
    parts = []
    for key, value in {'material_id': material['id'], 'date': date, 'client_key': client_key}.items():
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{key}"\r\n\r\n{value}\r\n'.encode())
    parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="media"; filename="demo-material.png"\r\nContent-Type: image/png\r\n\r\n'.encode() + image + b'\r\n')
    parts.append(f'--{boundary}--\r\n'.encode())
    multipart = b''.join(parts)
    started = time.monotonic()
    status, body = request('/api/v1/materials/media.php', multipart, 'multipart/form-data; boundary=' + boundary)
    elapsed = time.monotonic() - started
    result = json.loads(body)
    assert status == 200 and result.get('ok') is True, f'Upload failed HTTP {status}'
    assert elapsed >= max(0, health['upload_delay_seconds'] - 0.25), 'Configured delay was not observed'
    status, body = request('/api/v1/materials/media.php', multipart, 'multipart/form-data; boundary=' + boundary)
    retry = json.loads(body)
    assert status == 200 and retry.get('ok') is True, 'Idempotent retry failed'
    assert retry['media_id'] == result['media_id'] and retry['duplicate'] is True, 'Retry created another media record'
    updated = next(m for m in api('materials/today.php')['day']['materials'] if m['id'] == material['id'])
    media = [m for m in updated['media'] if m['id'] not in prior_ids]
    assert len(media) == 1 and media[0]['id'] == result['media_id'], 'Expected exactly one newly persisted media row'
    selected = media[0]
    target = urllib.parse.urlsplit(selected['url'])
    assert target.scheme == parsed.scheme and target.netloc == parsed.netloc, 'File URL left demo origin'
    status, downloaded = request(target.path + '?' + target.query)
    assert status == 200 and downloaded == image, 'Stored media byte readback differs'
    status, _ = request(target.path + '?' + target.query, authenticate=False)
    assert status == 401, 'Material file unexpectedly allowed anonymous access'
    status, device_body = request('/api/v1/materials/today.php', host='10.0.2.2:8765')
    assert status == 200
    device_material = next(m for m in json.loads(device_body)['day']['materials'] if m['id'] == material['id'])
    device_file = next(m for m in device_material['media'] if m['id'] == selected['id'])
    assert urllib.parse.urlsplit(device_file['url']).netloc == '10.0.2.2:8765', 'Device media URL did not preserve request Host'
    for blocked in ('/includes/config.php', '/api/v1/workspace_session.php', '/wacrm/index.php'):
        status, raw = request(blocked, authenticate=False)
        assert status == 404 and json.loads(raw)['code'] == 'demo_route_disabled', 'Non-demo route was exposed'
    report = {'demo_only': True, 'mtt_commit': fixture['mtt_commit'], 'user_id': user['id'], 'material_id': material['id'],
              'media_id': selected['id'], 'upload_elapsed_seconds': round(elapsed, 3), 'upload_delay_seconds': health['upload_delay_seconds'],
              'bytes': len(image), 'sha256': hashlib.sha256(image).hexdigest(),
              'checks': ['real HTTP login', 'materials list', 'condition write', 'multipart upload', 'idempotent retry', 'authenticated byte readback', 'anonymous media denied', 'emulator Host media URLs', 'non-demo routes denied']}
    api('logout.php', {})
    (root / 'smoke-report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
