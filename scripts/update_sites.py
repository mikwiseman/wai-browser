#!/usr/bin/env python3
"""Snapshot the official issued-domain registry. No runtime network dependency."""
import argparse
import datetime
import hashlib
import ipaddress
import json
import re
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = 'https://www.gosuslugi.ru/api/nsi/v1/custom/dic/tls/csv'
LEGACY = ['rzd.ru', 'tbank.ru', 'tbank-online.com', 'tinkoff.ru']


def ascii_name(value):
    return value.lower().encode('idna').decode('ascii')


RULES = set()
for line in (ROOT / 'resources/public_suffix_list.dat').read_text().splitlines():
    if line and not line.startswith('//'):
        prefix = '!' if line.startswith('!') else '*.' if line.startswith('*.') else ''
        RULES.add(prefix + ascii_name(line[len(prefix):]))


def domain(value):
    # The official CSV also contains «сайт.рф (xn--...)» rows.
    match = re.fullmatch(r'([^\s()]+)\s*\(([^\s()]+)\)', value)
    if match:
        first, second = (domain(part) for part in match.groups())
        if first != second:
            raise ValueError('IDN annotation mismatch')
        return first
    value = value.removeprefix('*.').removesuffix('.')
    try:
        value = ascii_name(value)
        ipaddress.ip_address(value)
    except UnicodeError:
        raise ValueError('Invalid IDN')
    except ValueError:
        pass
    else:
        raise ValueError('IP address')
    labels = value.split('.')
    if len(value) > 253 or any(not re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', label) for label in labels):
        raise ValueError('Invalid DNS name')
    suffix_count = 1
    for i in range(len(labels)):
        suffix = '.'.join(labels[i:])
        if '!' + suffix in RULES:
            suffix_count = len(labels) - i - 1
            break
        if suffix in RULES:
            suffix_count = max(suffix_count, len(labels) - i)
        if i > 0 and '*.' + suffix in RULES:
            suffix_count = max(suffix_count, len(labels) - i + 1)
    if len(labels) <= suffix_count:
        raise ValueError('Public suffix')
    return value


def decode(data):
    try:
        return data.decode('utf-8-sig')
    except UnicodeDecodeError:
        return data.decode('cp1251')


def parse_domains(data):
    return sorted({domain(line.strip()) for line in decode(data).splitlines() if line.strip()})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, help='Previously downloaded official CSV')
    args = parser.parse_args()
    if args.input:
        data = args.input.read_bytes()
    else:
        with urllib.request.urlopen(SOURCE, timeout=30) as response:
            data = response.read()
    names, rejected = set(LEGACY), []
    for line in decode(data).splitlines():
        if not line.strip():
            continue
        try:
            names.add(domain(line.strip()))
        except ValueError as error:
            rejected.append({'value': line, 'reason': str(error)})
    if len(names) < 100 or len(rejected) > len(names) / 10:
        raise SystemExit('Unexpected registry content; existing catalog left unchanged')
    # Preserve the exact registry scopes; only remove redundant descendants.
    names = sorted(name for name in names if not any('.'.join(name.split('.')[i:]) in names for i in range(1, len(name.split('.')))))
    result = {'source': SOURCE, 'retrievedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'sha256': hashlib.sha256(data).hexdigest(), 'sourceRows': len(data.splitlines()),
              'legacyDomains': LEGACY, 'excludedRows': rejected, 'domains': names}
    (ROOT / 'resources/certificates/sites.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'domains': len(names), 'excludedRows': rejected}, ensure_ascii=False))


if __name__ == '__main__':
    main()
