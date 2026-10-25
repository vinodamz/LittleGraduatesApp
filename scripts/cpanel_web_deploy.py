"""Deploy the generated web-release branch through cPanel's Git deployment.

Only app.thelittlegraduates.in is managed here. MTT and its database stay in
place. Credentials arrive from GitHub secrets and are never printed.
"""
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request


def api(module, function, **params):
    host = os.environ['CPANEL_HOST'].removeprefix('https://').removeprefix('http://').rstrip('/').split(':')[0]
    url = f'https://{host}:2083/execute/{module}/{function}'
    headers = {'Authorization': 'cpanel ' + os.environ['CPANEL_USER'] + ':' + os.environ['CPANEL_TOKEN'],
               'Accept': 'application/json', 'User-Agent': 'Mozilla/5.0 LittleGraduatesDeployment/1.0'}
    for attempt in range(8):
        try:
            request = urllib.request.Request(url, data=urllib.parse.urlencode(params).encode(), headers=headers)
            with urllib.request.urlopen(request, timeout=120) as response:
                result = json.load(response)
            if result.get('status') != 1:
                raise RuntimeError(f'{module}/{function} refused: {result.get("errors")}')
            return result
        except (urllib.error.URLError, json.JSONDecodeError):
            if attempt == 7:
                raise RuntimeError(f'{module}/{function}: hosting API unreachable') from None
            time.sleep(min(10 * 2 ** attempt, 60))


def deploy():
    user = os.environ['CPANEL_USER']
    root = f'/home/{user}/repos/LittleGraduatesAppWeb'
    domain = api('DomainInfo', 'single_domain_data', domain='app.thelittlegraduates.in')
    expected = f'/home/{user}/thelittlegraduates.in/app'
    if (domain.get('data') or {}).get('documentroot') != expected:
        raise RuntimeError('App document root is not the isolated app directory. Stopping.')
    repos = api('VersionControl', 'retrieve')
    if root not in json.dumps(repos.get('data')):
        api('VersionControl', 'create', type='git', name='LittleGraduatesAppWeb',
            repository_root=root, source_repository='https://github.com/vinodamz/LittleGraduatesApp.git')
    api('VersionControl', 'update', repository_root=root, branch='web-release')
    api('VersionControlDeployment', 'create', repository_root=root)
    sha = os.environ['SOURCE_SHA']
    for _ in range(20):
        try:
            url = 'https://app.thelittlegraduates.in/build-id.txt?release=' + sha
            with urllib.request.urlopen(url, timeout=15) as response:
                if response.read().decode().strip() == sha:
                    api('SSL', 'toggle_ssl_redirect_for_domains', domains='app.thelittlegraduates.in', state=1)
                    print('Verified HTTPS web release:', sha)
                    return
        except (urllib.error.URLError, UnicodeError):
            pass
        time.sleep(6)
    raise RuntimeError('cPanel deployment requested, but HTTPS release verification did not pass.')


if __name__ == '__main__':
    deploy()
