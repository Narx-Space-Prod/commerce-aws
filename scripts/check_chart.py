#!/usr/bin/env python3
"""Render enabled and disabled profiles; dummy digests never enter release state."""
import json
import os
import subprocess
import tempfile
from pathlib import Path

import yaml


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


with tempfile.TemporaryDirectory() as directory:
    actual_flags = ['-f', 'deploy/environment.yaml', '-f', 'deploy/release.json']
    run('helm', 'lint', '--strict', 'deploy/chart', *actual_flags)
    actual = subprocess.check_output(['helm', 'template', 'commerce', 'deploy/chart', '-n', 'commerce', *actual_flags], text=True)
    # Catch mistakes in the real reviewed deployment, as well as the fully enabled fixture.
    actual_path = Path(directory) / 'actual.yaml'
    actual_path.write_text(actual)
    values = Path(directory) / 'values.json'
    images = {name: '123456789012.dkr.ecr.ap-south-1.amazonaws.com/commerce-aws/' + name + '@sha256:' + 'a' * 64 for name in ('frontend', 'catalogue', 'orders', 'cart')}
    values.write_text(json.dumps({'enabled': True, 'release': {'source': 'a' * 40, 'images': images}}))
    flags = ['-f', 'deploy/config.example.yaml', '-f', str(values)]
    run('helm', 'lint', '--strict', 'deploy/chart', *flags)
    rendered = subprocess.check_output(['helm', 'template', 'commerce', 'deploy/chart', '-n', 'commerce', *flags], text=True)
    objects = list(yaml.safe_load_all(rendered))
    deployments = [obj for obj in objects if obj['kind'] == 'Deployment']
    assert len(deployments) == 6
    for obj in deployments:
        spec = obj['spec']['template']['spec']
        assert spec['securityContext']['runAsNonRoot']
        container = spec['containers'][0]
        assert container['securityContext']['readOnlyRootFilesystem']
        assert container['startupProbe'] and container['readinessProbe'] and container['livenessProbe']
    assert {obj['kind'] for obj in objects} >= {'Ingress', 'NetworkPolicy', 'ExternalSecret', 'ServiceMonitor', 'HorizontalPodAutoscaler'}
    manifest = Path(directory) / 'rendered.yaml'
    manifest.write_text(rendered)
    # All standard Kubernetes objects are checked strictly. Operator CRDs are checked by
    # rendering/structural assertions here; live CRD admission is part of AWS activation.
    run('kubeconform', '-strict', '-summary', '-kubernetes-version', '1.35.0',
        '-schema-location', 'https://raw.githubusercontent.com/yannh/kubernetes-json-schema/b2ba4defe30ed5a0104987433896f1fd32807304/{{.NormalizedKubernetesVersion}}-standalone-strict/{{.ResourceKind}}{{.KindSuffix}}.json',
        '-skip', 'SecretStore,ExternalSecret,ServiceMonitor,PrometheusRule', str(manifest), str(actual_path))
    missing = subprocess.run(['helm', 'template', 'commerce', 'deploy/chart', '--set', 'enabled=true'], capture_output=True)
    assert missing.returncode != 0, 'Missing release was incorrectly accepted'
    disabled = subprocess.check_output(['helm', 'template', 'commerce', 'deploy/chart'], text=True)
    assert not list(yaml.safe_load_all(disabled)), 'Unconfigured chart must not create workloads'
print('Enabled/disabled Helm profiles and workload security checks passed')
