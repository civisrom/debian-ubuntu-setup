#!/usr/bin/env python3
"""Public host facts and explicit SSH access for the minimal node installers."""
import argparse
import ipaddress
import json
import os
from pathlib import Path
import re
import stat
import subprocess

MARKER = '# VPNBOT_MANAGED_NODE_HOST'


def public(value, version=None):
    address = ipaddress.ip_address(value)
    if '%' in value or not address.is_global or address.is_multicast or (version and address.version != version):
        raise ValueError('A public unicast address is required')
    if address.version == 6 and (address not in ipaddress.ip_network('2000::/3') or address in ipaddress.ip_network('2002::/16')):
        raise ValueError('A public unicast address is required')
    return str(address)


def command(args):
    return subprocess.run(args, capture_output=True, text=True, timeout=30,
                          env={'PATH': '/usr/sbin:/usr/bin:/sbin:/bin', 'LANG': 'C.UTF-8'})


def ssh_source():
    parts = os.environ.get('SSH_CONNECTION', '').split()
    if not parts:
        return ''
    if len(parts) != 4 or not all(p.isdecimal() and 1 <= int(p) <= 65535 for p in (parts[1], parts[3])):
        raise ValueError('Invalid SSH connection metadata')
    return public(parts[0])


def ssh_ports():
    reply = command(['sshd', '-T'])
    if reply.returncode:
        raise ValueError('Cannot inspect effective SSH ports')
    ports = sorted({int(line.split()[1]) for line in reply.stdout.splitlines() if re.fullmatch(r'port [0-9]+', line)})
    if not ports:
        raise ValueError('Cannot inspect effective SSH ports')
    return ports


def discover():
    host = dict(interface='', public4='', public6='', routers=[], ssh_ports=ssh_ports())
    for version, target in ((4, '1.1.1.1'), (6, '2606:4700:4700::1111')):
        reply = command(['ip', '-j', '-'+str(version), 'route', 'get', target])
        if reply.returncode:
            continue
        routes = json.loads(reply.stdout)
        if len(routes) != 1:
            raise ValueError('Ambiguous WAN route')
        route = routes[0]
        interface = route.get('dev', '')
        if not re.fullmatch(r'[A-Za-z0-9_.-]{1,15}', interface):
            raise ValueError('Invalid WAN interface')
        reply = command(['ip', '-j', 'address', 'show', 'dev', interface])
        if reply.returncode:
            raise ValueError('Cannot inspect WAN addresses')
        unstable = {'tentative', 'dadfailed', 'temporary', 'deprecated'}
        assigned = [a['local'] for link in json.loads(reply.stdout) for a in link.get('addr_info', [])
                    if a.get('scope') == 'global' and a.get('family') == ('inet' if version == 4 else 'inet6')
                    and not unstable.intersection(a.get('flags', [])) and not any(a.get(flag) for flag in unstable)]
        source = route.get('prefsrc', route.get('src', ''))
        if source not in assigned:
            raise ValueError('Default route has no stable assigned source')
        source = public(source, version)
        if host['interface'] and host['interface'] != interface:
            raise ValueError('IPv4 and IPv6 use different WAN interfaces')
        host['interface'] = interface
        host['public'+str(version)] = source
        gateway = route.get('gateway', '')
        if version == 6 and gateway and ipaddress.ip_address(gateway).is_link_local:
            host['routers'] = [str(ipaddress.ip_address(gateway))]
    if not host['interface']:
        raise ValueError('Cannot discover public node address or SSH ports')
    return host


def block(text, pattern):
    masked = re.sub(r'#[^\n]*', lambda m: ' ' * len(m[0]), text)
    matches = list(re.finditer(pattern, masked, re.M))
    if len(matches) != 1:
        raise ValueError('Missing or ambiguous node firewall declaration')
    start, depth = matches[0].end(), 1
    for token in re.finditer(r'"(?:\\.|[^"\\])*"|#[^\n]*|[{}]', text[start:]):
        if token[0] == '{': depth += 1
        elif token[0] == '}': depth -= 1
        if depth == 0:
            return start, start+token.start()
    raise ValueError('Incomplete node firewall declaration')


def set_values(text, name, version, networks=False, routers=False):
    a, b = block(text, r'\bset\s+'+name+r'\s*\{')
    body = re.sub(r'#[^\n]*', '', text[a:b])
    if len(re.findall(r'\btype\s+ipv'+str(version)+r'_addr\s*;', body)) != 1:
        raise ValueError('Invalid node address set type')
    elements = list(re.finditer(r'\belements\s*=\s*\{([^{}]*)\}\s*;', body))
    if len(elements) > 1 or ('elements' in body and not elements):
        raise ValueError('Invalid node address set elements')
    values = []
    for token in (elements[0][1].split(',') if elements else []):
        token = token.strip()
        if not token:
            continue
        if routers:
            address = ipaddress.IPv6Address(token)
            if '%' in token or not address.is_link_local:
                raise ValueError('Only link-local IPv6 routers are permitted')
            values.append(str(address))
        elif networks:
            network = ipaddress.ip_network(token, strict=True)
            public(str(network.network_address), version)
            public(str(network.broadcast_address), version)
            if network.prefixlen == 0:
                raise ValueError('Unrestricted SSH network is forbidden')
            values.append(str(network))
        else:
            values.append(public(token, version))
    return values


def access(text):
    result = dict(sources=[], admins=[], ssh_networks=[])
    if MARKER not in text.splitlines():
        return result
    for version in (4, 6):
        for suffix, field in (('sources', 'sources'), ('admins', 'admins'), ('ssh', 'ssh_networks')):
            values = set_values(text, 'node'+str(version)+'_'+suffix, version, suffix == 'ssh')
            result[field].extend(values)
    for field in result:
        result[field] = sorted(set(result[field]))
    if any(len(result[name]) > 32 for name in ('sources', 'admins')) or len(result['ssh_networks']) > 100000:
        raise ValueError('Too many node access entries')
    return result


def read_profile(path):
    path = Path(path).absolute()
    for item in (path, *path.parents):
        if item.is_symlink() or (item.exists() and (item.stat().st_uid != 0 or item.stat().st_mode & 0o022)):
            raise ValueError('Unsafe node firewall profile path')
    if not path.exists():
        return ''
    info = path.stat()
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_size > 2*1024*1024:
        raise ValueError('Unsafe node firewall profile file')
    return path.read_text()


def defaults(path=Path('/etc/nftables.conf')):
    text = read_profile(path)
    saved = access(text)
    try:
        host = discover() | {'network_detected': True}
    except (ValueError, OSError, subprocess.SubprocessError):
        # Interactive enrollment still permits manual network selection. Its
        # preflight checks assigned addresses and SSH ports before any changes.
        # Bootstrap preparation stays strict and calls discover() directly.
        host = dict(interface='', public4='', public6='', routers=[], ssh_ports=ssh_ports(), network_detected=False)
        if MARKER in text.splitlines():
            wan = re.findall(r'(?m)^\s*define WAN\s*=\s*"([A-Za-z0-9_.-]{1,15})"\s*$', text)
            ipv4 = re.findall(r'(?m)^\s*define PUBLIC_IP\s*=\s*([0-9.]+)\s*$', text)
            if len(wan) == 1: host['interface'] = wan[0]
            if len(ipv4) == 1 and ipv4[0] != '0.0.0.0': host['public4'] = public(ipv4[0], 4)
            ipv6 = set_values(text, 'node6_public', 6)
            if len(ipv6) == 1: host['public6'] = ipv6[0]
    host.update(saved)
    if MARKER in text.splitlines():
        host['routers'] = sorted(set(host['routers']+set_values(text, 'ipv6_routers', 6, routers=True)))
    source = ssh_source()
    if source and source not in host['admins']:
        host['admins'].append(source)
    return host


def elements(text, name, values):
    a, b = block(text, r'\bset\s+'+name+r'\s*\{')
    body = re.sub(r'\belements\s*=\s*\{[^{}]*\}\s*;', '', text[a:b])
    if values:
        body = body.rstrip()+'\n        elements = { '+', '.join(values)+' };\n    '
    return text[:a]+body+text[b:]


def prepare(text, host, admins):
    if MARKER not in text.splitlines():
        raise ValueError('This is not a minimal node firewall profile')
    previous = access(text)
    admins = sorted(set(previous['admins']+[public(a) for a in admins]))
    source = ssh_source()
    if not admins or len(admins) > 32 or (source and source not in admins):
        raise ValueError('Explicit SSH administrators must include the current SSH source')
    if not host['public4'] and not host['public6']:
        raise ValueError('A public node address is required')
    if not re.fullmatch(r'[A-Za-z0-9_.-]{1,15}', host['interface']):
        raise ValueError('Invalid WAN interface')
    ports = sorted(set(host['ssh_ports']))
    if not ports or any(type(p) is not int or not 1 <= p <= 65535 or p in (80, 443) for p in ports):
        raise ValueError('Invalid SSH ports')
    replacements = {'WAN': '"'+host['interface']+'"',
                    'PUBLIC_IP': public(host['public4'], 4) if host['public4'] else '0.0.0.0',
                    'SERVER_SSH_PORTS': '{ '+', '.join(map(str, ports))+' }'}
    for name, value in replacements.items():
        text, count = re.subn(r'(?m)^(\s*define '+name+r'\s*=)[^\n]+', lambda m: m[1]+' '+value, text)
        if count != 1:
            raise ValueError('Missing or ambiguous node firewall definition')
    for version in (4, 6):
        text = elements(text, 'node'+str(version)+'_admins', [a for a in admins if ipaddress.ip_address(a).version == version])
        # Keep the pre-existing ASN/NODE_SSH_PORTS policy. Only explicit admins
        # gain the effective management ports; never open these ports to an ASN.
        pattern = r'(?m)^(\s*iifname \$WAN ip6? saddr @node'+str(version)+r'_admins tcp dport )\$(?:NODE|SERVER)_SSH_PORTS( .*)$'
        text, count = re.subn(pattern, r'\1$SERVER_SSH_PORTS\2', text)
        if count != 1:
            raise ValueError('Missing or ambiguous explicit SSH administrator rule')
    text = elements(text, 'node6_public', [public(host['public6'], 6)] if host['public6'] else [])
    routers = set_values(text, 'ipv6_routers', 6, routers=True)
    for value in host['routers']:
        address = ipaddress.IPv6Address(value)
        if '%' in value or not address.is_link_local:
            raise ValueError('Only link-local IPv6 routers are permitted')
        routers.append(str(address))
    text = elements(text, 'ipv6_routers', sorted(set(routers)))
    return text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    parser.add_argument('--admins', nargs='+', required=True)
    parser.add_argument('--ssh-ports', nargs='*', type=int, default=[])
    args = parser.parse_args()
    host = discover()
    if args.ssh_ports and sorted(set(args.ssh_ports)) != host['ssh_ports']:
        raise ValueError('Management ports must match the effective sshd ports')
    text = prepare(read_profile(args.source), host, args.admins)
    if args.destination.is_symlink() or args.destination.resolve() == args.source.resolve():
        raise ValueError('The candidate must be a separate regular file')
    args.destination.write_text(text)
    args.destination.chmod(0o600)
    print('Minimal node profile prepared: WAN='+host['interface']+', IPv4='+host['public4']+
          ', IPv6='+host['public6']+', SSH='+','.join(map(str, host['ssh_ports'])))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError):
        raise SystemExit('Cannot prepare the minimal node firewall: check assigned addresses, SSH ports and explicit administrators; current rules are unchanged')
