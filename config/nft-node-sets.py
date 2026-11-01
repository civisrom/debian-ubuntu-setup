#!/usr/bin/env python3
"""Create missing IPv6 node sets without changing elements, chains or policies."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

DECLARATIONS = {
    'node6_sources': 'set node6_sources { type ipv6_addr; }',
    'node6_public': 'set node6_public { type ipv6_addr; }',
    'egress6_snat': 'map egress6_snat { type ipv6_addr : ipv6_addr; }',
    'ipv6_routers': 'set ipv6_routers { type ipv6_addr; }',
}


def declarations(text):
    # A host-network minimal node has no container IPv6 SNAT mapping.
    return {name: value for name, value in DECLARATIONS.items()
            if not (name == 'egress6_snat' and '# VPNBOT_MANAGED_NODE_HOST' in text)}


def prepare(text):
    """Preserve all existing declarations, including populated sets."""
    start = re.search(r'(?m)^\s*table\s+ip6\s+filter\s*\{', text)
    if not start:
        return text.rstrip() + '\n\n# IPv6 node sets managed by the installers; no ports are opened.\n' + \
            'table ip6 filter {\n' + ''.join('    '+v+'\n' for v in declarations(text).values()) + '}\n'
    depth, end = 1, None
    for token in re.finditer(r'"(?:\\.|[^"\\])*"|#[^\n]*|[{}]', text[start.end():]):
        if token[0] == '{': depth += 1
        if token[0] == '}': depth -= 1
        if depth == 0:
            end = start.end() + token.start()
            break
    if end is None:
        raise ValueError('Incomplete IPv6 filter table')
    body = re.sub(r'#[^\n]*', '', text[start.end():end])
    missing = [v for k,v in declarations(text).items() if not re.search(r'\b(?:set|map)\s+'+k+r'\s*\{', body)]
    if not missing:
        return text
    return text[:start.end()] + '\n' + ''.join('    '+v+'\n' for v in missing) + text[start.end():]


def nft(args, data=None, check=True):
    p = subprocess.run(['nft', *args], input=data, capture_output=True, text=True, timeout=30)
    if check and p.returncode:
        raise RuntimeError('nftables validation or update failed; existing rules were preserved')
    return p


def trusted(path):
    for p in (path, *path.parents):
        if p.is_symlink() or (p.exists() and (p.stat().st_uid != 0 or p.stat().st_mode & 0o022)):
            raise ValueError('Configuration path must be root-owned without symlinks or shared write access')


def atomic(path, text, mode):
    fd, name = tempfile.mkstemp(prefix='.node6-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as f:
            os.fchmod(f.fileno(), mode)
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        os.replace(name, path)
    finally:
        Path(name).unlink(missing_ok=True)


def ensure(path):
    trusted(path)
    if path.exists() and (not path.is_file() or path.stat().st_nlink != 1):
        raise ValueError('Unsafe nftables configuration file')
    existed = path.exists()
    before = path.read_text() if existed else '#!/usr/sbin/nft -f\n'
    after = prepare(before)
    mode = path.stat().st_mode & 0o777 if existed else 0o600
    transaction = 'add table ip6 filter\n'
    for name, declaration in declarations(before).items():
        result = nft(['-j', 'list', 'set', 'ip6', 'filter', name], check=False)
        if result.returncode == 0:
            obj = next(x.get('set', x.get('map')) for x in json.loads(result.stdout)['nftables'] if 'set' in x or 'map' in x)
            if obj.get('type') != 'ipv6_addr' or obj.get('map') != ('ipv6_addr' if name == 'egress6_snat' else None):
                raise ValueError('Existing node set has an incompatible type; no changes made')
            continue
        kind, definition = declaration.split(' ', 1)
        transaction += 'add '+kind+' ip6 filter '+definition+'\n'
    # Check persistence and the small live transaction before making either change.
    nft(['-c', '-f', '-'], after)
    nft(['-c', '-f', '-'], transaction)
    if after != before:
        atomic(path, after, mode)
    try:
        nft(['-f', '-'], transaction)
    except Exception:
        if after != before:
            if existed: atomic(path, before, mode)
            else: path.unlink(missing_ok=True)
        raise
    print('IPv6 node sets exist; existing addresses and firewall rules preserved')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, default=Path('/etc/nftables.conf'))
    args = parser.parse_args()
    if os.geteuid() != 0:
        raise ValueError('Run as root')
    fd = os.open('/run/lock/nft-docker-watch.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        ensure(args.config.absolute())
    finally:
        os.close(fd)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, RuntimeError, OSError, subprocess.SubprocessError):
        raise SystemExit('Cannot initialize IPv6 node sets; check nftables configuration and file permissions')
