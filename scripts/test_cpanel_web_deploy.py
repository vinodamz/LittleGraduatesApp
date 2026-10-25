import io
import os
import unittest
from unittest.mock import patch

import cpanel_web_deploy as deployment


class WebDeploymentTests(unittest.TestCase):
    def test_refuses_to_deploy_into_mtt_document_root(self):
        with patch.dict(os.environ, {'CPANEL_USER': 'school', 'SOURCE_SHA': 'release'}), patch.object(deployment, 'api', return_value={'data': {'documentroot': '/home/school/thelittlegraduates.in/mtt'}}) as api:
            with self.assertRaisesRegex(RuntimeError, 'isolated app directory'):
                deployment.deploy()
            self.assertEqual(api.call_count, 1)

    def test_existing_repository_deploys_web_branch_and_verifies_https_sha(self):
        root = '/home/school/repos/LittleGraduatesAppWeb'
        responses = [{'data': {'documentroot': '/home/school/thelittlegraduates.in/app'}},
                     {'data': [{'repository_root': root}]}, {'status': 1}, {'status': 1}, {'status': 1}]
        with patch.dict(os.environ, {'CPANEL_USER': 'school', 'SOURCE_SHA': 'release'}), patch.object(deployment, 'api', side_effect=responses) as api, patch.object(deployment.urllib.request, 'urlopen', return_value=io.BytesIO(b'release')) as request:
            deployment.deploy()
            self.assertEqual(api.call_args_list[2].args, ('VersionControl', 'update'))
            self.assertEqual(api.call_args_list[2].kwargs['branch'], 'web-release')
            self.assertEqual(api.call_args_list[3].args, ('VersionControlDeployment', 'create'))
            self.assertTrue(request.call_args.args[0].startswith('https://app.thelittlegraduates.in/'))

    def test_new_repository_uses_structured_clone_source(self):
        import json
        responses = [{'data': {'documentroot': '/home/school/thelittlegraduates.in/app'}},
                     {'data': []}, {'status': 1}, {'status': 1}, {'status': 1}, {'status': 1}]
        with patch.dict(os.environ, {'CPANEL_USER': 'school', 'SOURCE_SHA': 'release'}), patch.object(deployment, 'api', side_effect=responses) as api, patch.object(deployment.urllib.request, 'urlopen', return_value=io.BytesIO(b'release')):
            deployment.deploy()
            clone = api.call_args_list[2]
            self.assertEqual(clone.args, ('VersionControl', 'create'))
            self.assertEqual(json.loads(clone.kwargs['source_repository']), {'remote_name': 'origin', 'url': 'https://github.com/vinodamz/LittleGraduatesApp.git'})


if __name__ == '__main__':
    unittest.main()
