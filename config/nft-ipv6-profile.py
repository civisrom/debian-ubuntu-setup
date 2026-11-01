#!/usr/bin/env python3
"""Prepare the IPv6 sets of a supported nftables profile before atomic apply."""
import argparse
import ipaddress
import json
from pathlib import Path
import re
import subprocess
import sys

SETS = {
    'node6_sources': 'set node6_sources {\n        type ipv6_addr;\n    }',
    'node6_public': 'set node6_public {\n        type ipv6_addr;\n    }',
    'ipv6_routers': 'set ipv6_routers {\n        type ipv6_addr;\n    }',
    'egress6_snat': 'map egress6_snat {\n        type ipv6_addr : ipv6_addr;\n    }',
}


def address(value, *, router=False):
    try:
        addr = ipaddress.IPv6Address(value)
    except ValueError:
        raise ValueError('An individual IPv6 address is required; no prefix, scope or hostname') from None
    if '%' in value or (router and not addr.is_link_local) or (not router and not addr.is_global):
        raise ValueError('Use link-local IPv6 only for the router, public unicast IPv6 for node addresses')
    if addr.is_multicast or addr.is_unspecified:
        raise ValueError('Multicast and unspecified IPv6 are not permitted')
    return str(addr)


def block_pattern(name):
    return rf'(?ms)^    (?:set|map) {name} \{{\n.*?^    \}}'


def prepare(text, public=None, sources=None, routers=None):
    # Do not add IPv6 ACCEPT rules to an unrelated/old firewall.
    if 'table ip6 filter {' not in text:
        raise ValueError('This profile lacks the supported IPv6 firewall; update the /opt archive first')
    for chain in ('input', 'forward'):
        if not re.search(r'chain '+chain+r'\s*\{\s*type filter hook '+chain+r' priority 0; policy drop;',
                         text[text.index('table ip6 filter {'):]):
            raise ValueError('The IPv6 profile must keep input and forward DROP policies')
    minimal_node = '# VPNBOT_MANAGED_NODE_HOST' in text
    declarations = {name: declaration for name, declaration in SETS.items()
                    if not (minimal_node and name == 'egress6_snat')}
    for name, declaration in declarations.items():
        count = len(re.findall(block_pattern(name), text))
        if count > 1:
            raise ValueError('Ambiguous IPv6 set declaration')
        if not count:
            text = text.replace('table ip6 filter {', 'table ip6 filter {\n    '+declaration, 1)
    values = {}
    if public is not None:
        public = address(public)
        values['node6_public'] = ('set', 'ipv6_addr', public)
        if not minimal_node:
            values['egress6_snat'] = ('map', 'ipv6_addr : ipv6_addr', 'fd42:7662:6::9 : '+public)
    if sources is not None:
        values['node6_sources'] = ('set', 'ipv6_addr', ', '.join(sorted(set(address(a) for a in sources))))
    if routers is not None:
        values['ipv6_routers'] = ('set', 'ipv6_addr', ', '.join(sorted(set(address(a, router=True) for a in routers))))
    for name, (kind, datatype, elements) in values.items():
        declaration = f'    {kind} {name} {{\n        type {datatype};\n'
        if elements:
            declaration += f'        elements = {{ {elements} }};\n'
        declaration += '    }'
        text, count = re.subn(block_pattern(name), lambda _: declaration, text)
        if count != 1:
            raise ValueError('IPv6 set replacement was not unique')
    return text


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('source', type=Path)
    p.add_argument('destination', type=Path)
    p.add_argument('--public-ipv6')
    p.add_argument('--trusted-ipv6', nargs='*')
    p.add_argument('--router-ipv6', nargs='*')
    p.add_argument('--interface')
    args = p.parse_args()
    if args.public_ipv6:
        public = address(args.public_ipv6)
        if not args.interface or not re.fullmatch(r'[A-Za-z0-9_.:-]{1,15}', args.interface):
            raise ValueError('Specify the actual WAN interface')
        addresses = json.loads(subprocess.check_output(['ip', '-j', '-6', 'addr', 'show', 'dev', args.interface], text=True))
        unstable = {'tentative', 'dadfailed', 'temporary', 'deprecated'}
        assigned = [a['local'] for link in addresses for a in link.get('addr_info', [])
                    if a.get('scope') == 'global' and not set(a.get('flags', [])).intersection(unstable)
                    and not any(a.get(flag) for flag in unstable)]
        if public not in [str(ipaddress.IPv6Address(a)) for a in assigned]:
            raise ValueError('The chosen IPv6 is not a stable assigned address on this interface')
    text = prepare(args.source.read_text(), args.public_ipv6, args.trusted_ipv6, args.router_ipv6)
    if args.destination.is_symlink():
        raise ValueError('Destination must not be a symlink')
    args.destination.write_text(text)
    args.destination.chmod(0o600)
    print('IPv6 sets prepared; verify the complete candidate with nft -c before applying')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError):
        print('Cannot prepare IPv6 profile: check addresses, interface and the current profile format', file=sys.stderr)
        sys.exit(1)
