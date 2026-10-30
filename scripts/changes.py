#!/usr/bin/env python3
"""Select affected images. Git diffs never execute source from a PR."""
import json
import os
import subprocess

COMPONENTS = {
    'frontend': 'application/frontend',
    'catalogue': 'application/catalogue',
    'orders': 'application/orders',
    'cart': 'application/orders/cart',
}


def select(paths):
    if any(p.startswith(('.github/workflows/', 'scripts/')) for p in paths):
        return list(COMPONENTS)
    selected = set()
    for path in paths:
        for name, context in COMPONENTS.items():
            if name == 'orders' and path.startswith('application/orders/cart/'):
                continue
            if path.startswith(context + '/') and not path.endswith(('.md', '/LICENSE')):
                selected.add(name)
    return [name for name in COMPONENTS if name in selected]


if __name__ == '__main__':
    with open(os.environ['GITHUB_EVENT_PATH']) as source:
        event = json.load(source)
    base = event.get('pull_request', {}).get('base', {}).get('sha') or event.get('before')
    if not base or set(base) == {'0'}:
        names = list(COMPONENTS)
    else:
        paths = subprocess.check_output(['git', 'diff', '--name-only', '-z', base, 'HEAD']).decode().split('\0')
        names = select(paths)
    matrix = {'include': [{'component': name, 'context': COMPONENTS[name]} for name in names]}
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        output.write('matrix=' + json.dumps(matrix) + '\n')
        output.write('changed=' + str(bool(names)).lower() + '\n')
    print('Images requiring build:', ', '.join(names) or 'none')
