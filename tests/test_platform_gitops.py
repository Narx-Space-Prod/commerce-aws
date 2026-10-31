from pathlib import Path
import re
import json
import os
import shutil
import subprocess
import tempfile
import unittest
import yaml

ROOT = Path(__file__).parents[1]


class PlatformOwnership(unittest.TestCase):
    def test_platform_sources_are_pinned_and_contained(self):
        bootstrap = list(yaml.safe_load_all((ROOT / 'deploy/platform-root.yaml').read_text()))
        project = next(x for x in bootstrap if x['kind'] == 'AppProject')
        parent = next(x for x in bootstrap if x['kind'] == 'Application')
        self.assertFalse(parent['metadata'].get('finalizers'))
        applications = list(yaml.safe_load_all((ROOT / 'deploy/platform/apps/applications.yaml').read_text()))
        self.assertEqual(len(applications), 6)
        versions = set()
        for app in applications:
            self.assertEqual(app['spec']['project'], 'platform')
            self.assertIn('resources-finalizer.argocd.argoproj.io', app['metadata']['finalizers'])
            destination = app['spec']['destination']
            self.assertIn(destination, project['spec']['destinations'])
            for source in app['spec'].get('sources', [app['spec'].get('source')]):
                self.assertIn(source['repoURL'], project['spec']['sourceRepos'])
                if 'chart' in source:
                    self.assertRegex(str(source['targetRevision']), r'^v?\d+\.\d+\.\d+$')
                    versions.add(source['chart'])
                for file in source.get('helm', {}).get('valueFiles', []):
                    self.assertTrue(file.startswith('$values/deploy/platform/'))
                    self.assertTrue((ROOT / file.removeprefix('$values/')).is_file())
        self.assertEqual(versions, {'external-secrets', 'metrics-server', 'aws-load-balancer-controller', 'kube-prometheus-stack', 'cert-manager'})

    def test_certificates_and_tracking_have_a_single_owner(self):
        argo = yaml.safe_load((ROOT / 'deploy/platform/argo-values.yaml').read_text())
        self.assertEqual(argo['configs']['cm']['application.resourceTrackingMethod'], 'annotation')
        self.assertEqual(argo['configs']['repositories']['cert-manager-oci']['enableOCI'], 'true')
        ingress = yaml.safe_load((ROOT / 'deploy/platform/ingress-values.yaml').read_text())
        monitoring = yaml.safe_load((ROOT / 'deploy/platform/monitoring-values.yaml').read_text())
        self.assertTrue(ingress['enableCertManager'])
        self.assertTrue(monitoring['prometheusOperator']['admissionWebhooks']['certManager']['enabled'])
        apps = {x['metadata']['name']: x for x in yaml.safe_load_all((ROOT / 'deploy/platform/apps/applications.yaml').read_text())}
        for name in ['platform-ingress', 'platform-monitoring']:
            spec = apps[name]['spec']
            self.assertIn('RespectIgnoreDifferences=true', spec['syncPolicy']['syncOptions'])
            self.assertEqual(len(spec['syncPolicy']['syncOptions']), len(set(spec['syncPolicy']['syncOptions'])))
            for rule in spec['ignoreDifferences']:
                self.assertEqual(rule['group'], 'admissionregistration.k8s.io')
                self.assertEqual(rule['jqPathExpressions'], ['.webhooks[].clientConfig.caBundle'])
        def wave(name):
            return int(apps[name]['metadata'].get('annotations', {}).get('argocd.argoproj.io/sync-wave', '0'))
        self.assertLess(wave('platform-baseline'), wave('platform-cert-manager'))
        self.assertLess(wave('platform-cert-manager'), wave('platform-monitoring'))

    def test_teardown_orders_controller_cleanup(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'deploy/platform').mkdir(parents=True)
            shutil.copy(ROOT / 'deploy/platform/versions.env', root / 'deploy/platform/versions.env')
            (root / 'bin').mkdir()
            stub = """#!/usr/bin/python3
import sys,os,json,pathlib
name=pathlib.Path(sys.argv[0]).name;a=sys.argv[1:]
with open('calls.jsonl','a') as f:f.write(json.dumps([name,*a])+'\\n')
if name=='terraform':
 print(json.dumps({k:{'value':v} for k,v in {'account_id':'123456789012','region':'ap-south-1','cluster_name':'commerce-aws','vpc_id':'vpc-0123456789abcdef0'}.items()}))
elif name=='aws':
 if a[:2]==['sts','get-caller-identity']:print('123456789012')
 elif a[:2]==['eks','describe-cluster']:print('https://test.eks.invalid')
elif name=='kubectl':
 if a[:2]==['config','current-context']:print('commerce-aws')
 elif a[:2]==['config','view']:print('https://test.eks.invalid')
 elif 'get' in a and 'application' in a:print('application/found')
"""
            for tool in ['terraform', 'aws', 'kubectl', 'helm']:
                path = root / 'bin' / tool
                path.write_text(stub)
                path.chmod(0o700)
            env = dict(os.environ, PATH=str(root / 'bin') + ':' + os.environ['PATH'], CONFIRM_DESTROY='destroy commerce-aws')
            result = subprocess.run(['bash', str(ROOT / 'scripts/platform.sh'), 'teardown'], cwd=root, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            calls = [json.loads(x) for x in (root / 'calls.jsonl').read_text().splitlines()]
            def find(*parts):
                return next(i for i, call in enumerate(calls) if all(p in call for p in parts))
            root_delete = find('delete', 'application', 'platform-root')
            patches = [i for i, call in enumerate(calls) if 'patch' in call]
            self.assertEqual(len(patches), 6)
            self.assertLess(root_delete, min(patches))
            self.assertLess(max(patches), find('delete', 'namespace', 'commerce'))
            self.assertLess(find('delete', 'application', 'platform-monitoring'), find('delete', 'pvc'))
            self.assertLess(find('delete', 'pvc'), find('delete', 'application', 'platform-ingress'))
            self.assertLess(find('delete', 'application', 'platform-ingress'), find('delete', 'application', 'platform-cert-manager'))
            self.assertLess(find('delete', 'application', 'platform-cert-manager'), find('delete', 'application', 'platform-baseline'))
            self.assertLess(find('delete', 'application', 'platform-baseline'), find('helm', 'uninstall', 'argocd'))

    def test_only_argocd_remains_owned_by_helm_bootstrap(self):
        script = (ROOT / 'scripts/platform.sh').read_text()
        installs = re.findall(r'helm upgrade --install ([\w-]+)', script)
        removals = re.findall(r'helm uninstall ([\w-]+)', script)
        self.assertEqual(installs, ['argocd'])
        self.assertEqual(removals, ['argocd'])


if __name__ == '__main__':
    unittest.main()
