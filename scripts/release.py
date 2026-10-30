#!/usr/bin/env python3
"""Merge publisher records into one reviewed deployment manifest; no YAML dependency."""
import argparse
import json
import re
from pathlib import Path

COMPONENTS = {'frontend', 'catalogue', 'orders', 'cart'}
IMAGE = re.compile(r'^([0-9]{12})\.dkr\.ecr\.([a-z0-9-]+)\.amazonaws\.com/commerce-aws/(frontend|catalogue|orders|cart)@sha256:[a-f0-9]{64}$')


def validate(document, account=None, region=None):
    release = document['release']
    images = release['images']
    if not images and release['source'] == '':
        return  # Initial unconfigured scaffold.
    if set(images) != COMPONENTS or not re.fullmatch('[a-f0-9]{40}', release['source']):
        raise ValueError('A release needs a source commit and exactly four images')
    locations = set()
    for name, image in images.items():
        match = IMAGE.fullmatch(image)
        if not match or match[3] != name:
            raise ValueError('Image must name its matching ECR component by digest')
        locations.add((match[1], match[2]))
    if len(locations) != 1 or (account and locations != {(account, region)}):
        raise ValueError('All images must use the intended AWS account and region')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--records', type=Path)
    parser.add_argument('--source')
    parser.add_argument('--account')
    parser.add_argument('--region')
    args = parser.parse_args()
    path = Path('deploy/release.json')
    document = json.loads(path.read_text())
    if args.records:
        if not args.source or not args.account or not args.region:
            parser.error('Publishing requires source, account and region')
        records = list(args.records.glob('**/release-*.json'))
        if not records:
            raise ValueError('Publisher records are missing')
        for record in records:
            payload = json.loads(record.read_text())
            if payload['component'] not in COMPONENTS or payload['source'] != args.source:
                raise ValueError('Unexpected publisher record')
            document['release']['images'][payload['component']] = payload['image']
        document['release']['source'] = args.source
    validate(document, args.account, args.region)
    if args.records:
        path.write_text(json.dumps(document, indent=2, sort_keys=True) + '\n')
