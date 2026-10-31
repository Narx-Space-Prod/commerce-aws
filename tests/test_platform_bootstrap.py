import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).parents[1]


class PlatformBootstrap(unittest.TestCase):
    def execute(self, operation, outputs=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'deploy/platform').mkdir(parents=True)
            shutil.copy(ROOT / 'deploy/platform/versions.env', root / 'deploy/platform/versions.env')
            (root / 'bin').mkdir()
            stub = '''#!/usr/bin/python3
import json,os,pathlib,sys
name=pathlib.Path(sys.argv[0]).name;args=sys.argv[1:]
if name=='helm':
 if args[0]=='pull':
  chart=args[1];version=args[args.index('--version')+1];dest=pathlib.Path(args[args.index('--destination')+1]);(dest/(chart+'-'+version+'.tgz')).write_text('test chart')
 sys.exit(0)
if name=='terraform' and args[-2:]==['output','-json']:
 print(os.environ['TEST_OUTPUTS']);sys.exit(0)
pathlib.Path('unexpected-operation').write_text(name);sys.exit(77)
'''
            for tool in ['helm', 'terraform', 'aws', 'kubectl', 'jq']:
                path = root / 'bin' / tool
                path.write_text(stub)
                path.chmod(0o700)
            environment = dict(os.environ, PATH=str(root / 'bin') + ':' + os.environ['PATH'], TEST_OUTPUTS=json.dumps(outputs or {}))
            run = subprocess.run(['bash', str(ROOT / 'scripts/platform.sh'), operation], cwd=root, env=environment, capture_output=True, text=True)
            candidate = root / '.work/environment.generated.json'
            controller = root / '.work/platform-ingress.generated.json'
            return run, json.loads(candidate.read_text()) if candidate.exists() else None, (root / 'unexpected-operation').exists(), json.loads(controller.read_text()) if controller.exists() else None

    def outputs(self):
        return {key: {'value': value} for key, value in {
            'account_id': '123456789012', 'region': 'ap-south-1', 'cluster_name': 'commerce-aws', 'vpc_id': 'vpc-0123456789abcdef0',
            'runtime_secret_arn': 'arn:aws:secretsmanager:ap-south-1:123456789012:secret:runtime',
            'database_secret_arn': 'arn:aws:secretsmanager:ap-south-1:123456789012:secret:database'
        }.items()}

    def test_prepare_is_independent_of_aws_cluster_and_application_release(self):
        result, _, unexpected, _ = self.execute('prepare')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(unexpected)

    def test_configuration_is_disabled_and_uses_only_output_identifiers(self):
        result, values, unexpected, controller = self.execute('configure', self.outputs())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(unexpected)
        self.assertFalse(values['enabled'])
        self.assertFalse(values['ingress']['enabled'])
        self.assertEqual(values['region'], 'ap-south-1')
        self.assertEqual(controller['vpcId'], 'vpc-0123456789abcdef0')
        self.assertEqual(controller['clusterName'], 'commerce-aws')
        self.assertTrue(controller['enableCertManager'])

    def test_cross_account_secret_is_rejected(self):
        outputs = self.outputs()
        outputs['runtime_secret_arn']['value'] = 'arn:aws:secretsmanager:ap-south-1:999999999999:secret:runtime'
        result, candidate, unexpected, _ = self.execute('configure', outputs)
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(candidate)
        self.assertFalse(unexpected)


if __name__ == '__main__':
    unittest.main()
