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
        '-skip', 'SecretStore,ExternalSecret,ServiceMonitor,PrometheusRule', str(manifest))
    missing = subprocess.run(['helm', 'template', 'commerce', 'deploy/chart', '--set', 'enabled=true'], capture_output=True)
    assert missing.returncode != 0, 'Missing release was incorrectly accepted'
    disabled = subprocess.check_output(['helm', 'template', 'commerce', 'deploy/chart'], text=True)
    assert not list(yaml.safe_load_all(disabled)), 'Unconfigured chart must not create workloads'
print('Enabled/disabled Helm profiles and workload security checks passed')
