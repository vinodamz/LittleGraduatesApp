import argparse
import tempfile
import unittest
from pathlib import Path
from play_release import release, version_code


class Reply:
    content = b'{}'
    def __init__(self, data): self.data = data
    def raise_for_status(self): pass
    def json(self): return self.data


class Session:
    def __init__(self, tested=True, uploaded='1001'):
        self.calls = []
        self.tested, self.uploaded = tested, uploaded
    def request(self, method, url, **kwargs):
        self.calls.append((method, url, kwargs))
        if method == 'POST' and url.endswith('/edits'): return Reply({'id': 'edit'})
        if 'uploadType=media' in url: return Reply({'versionCode': self.uploaded})
        if method == 'GET': return Reply({'releases': [{'status': 'completed', 'versionCodes': ['1001' if self.tested else '999']}]})
        return Reply({})


class ReleaseTests(unittest.TestCase):
    def test_promotes_only_tested_version_and_validates_before_commit(self):
        s = Session()
        release(s, 'promote', '1001')
        self.assertEqual(s.calls[2][2]['json']['releases'][0]['versionCodes'], ['1001'])
        self.assertTrue(s.calls[-2][1].endswith(':validate'))
        self.assertTrue(s.calls[-1][1].endswith(':commit'))
    def test_unavailable_version_aborts_edit_without_publication(self):
        s = Session(tested=False)
        with self.assertRaises(ValueError): release(s, 'promote', '1001')
        self.assertEqual(s.calls[-1][0], 'DELETE')
        self.assertFalse(any(x[1].endswith(':commit') for x in s.calls))
    def test_upload_checks_embedded_version_code(self):
        with tempfile.TemporaryDirectory() as folder:
            bundle = Path(folder) / 'app.aab'
            bundle.write_bytes(b'fake bundle')
            s = Session(uploaded='999')
            with self.assertRaises(ValueError): release(s, 'upload', '1001', bundle)
            self.assertEqual(s.calls[-1][0], 'DELETE')
    def test_version_limits(self):
        for code in ['0', '-1', 'abc', '2100000001']:
            with self.assertRaises(argparse.ArgumentTypeError): version_code(code)
        self.assertEqual(version_code('1001'), '1001')


if __name__ == '__main__': unittest.main()
