#!/usr/bin/env python3
"""Fail if a required payment test is absent, skipped, or unsuccessful."""
import argparse
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET


def android_results(directory):
    results = {}
    for path in Path(directory).rglob('TEST-*.xml'):
        for case in ET.parse(path).iter('testcase'):
            key = case.get('classname', '').rsplit('.', 1)[-1] + '/' + case.get('name', '').removesuffix('()')
            passed = not any(case.find(tag) is not None for tag in ('failure', 'error', 'skipped'))
            results.setdefault(key, []).append(passed)
    return results


def ios_results(bundles):
    results = {}
    def walk(node):
        if node.get('nodeType') == 'Test Case':
            key = node['nodeIdentifier'].removesuffix('()')
            results.setdefault(key, []).append(node.get('result') == 'Passed')
        for child in node.get('children', []):
            walk(child)
    for bundle in bundles:
        data = json.loads(subprocess.check_output([
            'xcrun', 'xcresulttool', 'get', 'test-results', 'tests', '--path', bundle, '--format', 'json']))
        for node in data['testNodes']:
            walk(node)
    return results


def missing_tests(manifest, platform, tier, results):
    required = manifest[platform]['pr'] + (manifest[platform]['full'] if tier == 'full' else [])
    return [name for name in required if not results.get(name) or not all(results[name])]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=['ios', 'android'], required=True)
    parser.add_argument('--tier', choices=['pr', 'full'], default='pr')
    parser.add_argument('results', nargs='+')
    args = parser.parse_args()
    manifest = json.loads(Path(__file__).with_name('coverage.json').read_text())
    results = ios_results(args.results) if args.platform == 'ios' else android_results(args.results[0])
    missing = missing_tests(manifest, args.platform, args.tier, results)
    if missing:
        parser.exit(1, 'Required payment tests missing, skipped, or failed:\n' + '\n'.join(missing) + '\n')
    count = len(manifest[args.platform]['pr']) + (len(manifest[args.platform]['full']) if args.tier == 'full' else 0)
    print(f'Payment coverage: {count} required tests passed ({args.platform}/{args.tier}).')


if __name__ == '__main__':
    main()
