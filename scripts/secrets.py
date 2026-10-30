#!/usr/bin/env python3
"""Write a single scoped secret via stdin, with no secret in argv, output or files."""
import base64
import getpass
import json
import secrets
import subprocess
import sys
from urllib.parse import urlparse

if subprocess.check_output(['kubectl', 'config', 'current-context'], text=True).strip() != 'commerce-aws':
    raise SystemExit('Select the dedicated commerce-aws EKS context first')
kind = sys.argv[1] if len(sys.argv) == 2 else ''
if kind not in {'grafana', 'slack'}:
    raise SystemExit('Usage: python3 scripts/secrets.py grafana|slack')
name = 'grafana-admin' if kind == 'grafana' else 'slack-notifications'
existing = subprocess.run(['kubectl', '--context', 'commerce-aws', '-n', 'monitoring', 'get', 'secret', name, '-o', 'name'], capture_output=True)
if existing.returncode == 0:
    print('Existing secret preserved:', name)
    raise SystemExit(0)
if kind == 'grafana':
    data = {'admin-user': 'admin', 'admin-password': secrets.token_urlsafe(32)}
else:
    webhook = getpass.getpass('Dedicated Slack incoming webhook (hidden): ').strip()
    url = urlparse(webhook)
    if url.scheme != 'https' or url.hostname != 'hooks.slack.com' or not url.path.startswith('/services/'):
        raise SystemExit('Expected an HTTPS Slack incoming webhook')
    data = {'webhook': webhook}
manifest = {'apiVersion': 'v1', 'kind': 'Secret', 'metadata': {'name': name, 'namespace': 'monitoring'},
            'type': 'Opaque', 'data': {key: base64.b64encode(value.encode()).decode() for key, value in data.items()}}
subprocess.run(['kubectl', '--context', 'commerce-aws', 'apply', '-f', '-'], input=json.dumps(manifest), text=True, check=True, stdout=subprocess.DEVNULL)
print('Secret created:', name)
