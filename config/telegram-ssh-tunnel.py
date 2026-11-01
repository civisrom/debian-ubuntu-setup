#!/usr/bin/env python3
"""Restricted Telegram SSH forwarding; no bot token is needed or read."""
import argparse
import fcntl
import ipaddress
import json
import os
from pathlib import Path
import pwd
import re
import shutil
import subprocess
import sys
import tempfile

CONF = Path('/etc/vpnbot-telegram')
STATE = Path('/var/lib/vpnbot-telegram')
USER = 'vpb-tg'
UNIT = Path('/etc/systemd/system')
DROPIN = Path('/etc/ssh/sshd_config.d/00-system-setup-telegram.conf')


def run(args, *, check=True, **kwargs):
    p = subprocess.run(args, text=True, stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, **kwargs)
    if check and p.returncode:
        # SSH/config errors may contain addresses, usernames or configuration data.
        raise RuntimeError(f'{Path(args[0]).name}: command failed ({p.returncode})')
    return p


def host(value):
    try:
        return str(ipaddress.ip_address(value))
    except ValueError:
        if len(value) <= 253 and all(re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?', s)
                                     for s in value.split('.')):
            return value
        raise argparse.ArgumentTypeError('Use an IP address or DNS hostname without a scheme or port') from None


def source(value):
    try:
        addr = ipaddress.ip_address(value)
        if '%' in value or not addr.is_global or addr.is_multicast:
            raise ValueError()
        return str(addr)
    except ValueError:
        raise argparse.ArgumentTypeError('Use one public source IP, without a subnet') from None


def username(value):
    if re.fullmatch(r'[a-z][a-z0-9_-]{0,30}', value) and value != 'root':
        return value
    raise argparse.ArgumentTypeError('Use a dedicated non-root account name')


def port(value):
    if value.isascii() and value.isdigit() and 1 <= int(value) <= 65535:
        return int(value)
    raise argparse.ArgumentTypeError('Port must be 1..65535')


def public_key(path):
    # Only OpenSSH PUBLIC keys. Values are never included in errors.
    p = Path(path)
    if p.suffix != '.pub' or p.is_symlink() or not p.is_file() or p.stat().st_size > 16384:
        raise ValueError('Invalid public key file')
    value = p.read_text().strip().split()
    if len(value) < 2 or value[0] not in ('ssh-ed25519', 'ssh-rsa', 'ecdsa-sha2-nistp256'):
        raise ValueError('An OpenSSH public key is required')
    if not re.fullmatch(r'[A-Za-z0-9+/]+={0,2}', value[1]):
        raise ValueError('Invalid public key encoding')
    run(['ssh-keygen', '-l', '-f', str(p)])
    return ' '.join(value[:2])


def safe_dir(path, mode=0o755):
    for parent in (path, *path.parents):
        if parent.is_symlink() or (parent.exists() and (parent.stat().st_uid != 0 or parent.stat().st_mode & 0o022)):
            raise ValueError('Directory ancestry must be root-owned without symlinks or shared write access')
    created = not path.exists()
    path.mkdir(mode=mode, parents=True, exist_ok=True)
    if path.stat().st_uid != 0 or path.stat().st_mode & 0o022:
        raise ValueError('Configuration directory must be root-owned and not writable by others')
    if created or path in (CONF, STATE):
        path.chmod(mode)


def write(path, value, mode=0o644):
    safe_dir(path.parent)
    if path.is_symlink() or (path.exists() and (not path.is_file() or path.stat().st_nlink != 1)):
        raise ValueError('Unsafe destination file')
    fd, tmp = tempfile.mkstemp(prefix='.telegram-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as f:
            os.fchmod(f.fileno(), mode)
            f.write(value)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def account(name, home):
    try:
        u = pwd.getpwnam(name)
        if u.pw_uid == 0 or u.pw_shell not in ('/usr/sbin/nologin', '/sbin/nologin') or u.pw_dir != home:
            raise ValueError('Existing account is not a dedicated forwarding account')
    except KeyError:
        run(['useradd', '--system', '--home-dir', home, '--shell', '/usr/sbin/nologin', name])


def prepare_key():
    account(USER, str(STATE))
    safe_dir(STATE, 0o755)
    # Private files are created by ssh-keygen and never read by this program.
    keydir = STATE / 'keys'
    if keydir.is_symlink():
        raise ValueError('Unsafe key directory')
    keydir.mkdir(mode=0o700, exist_ok=True)
    u = pwd.getpwnam(USER)
    if keydir.stat().st_uid not in (0, u.pw_uid):
        raise ValueError('Unexpected key directory owner')
    os.chown(keydir, u.pw_uid, u.pw_gid)
    keydir.chmod(0o700)
    for name in ('relay', 'local'):
        key = keydir / ('id_ed25519_' + name)
        if key.is_symlink():
            raise ValueError('Unsafe key path')
        if not key.exists():
            run(['runuser', '-u', USER, '--', 'ssh-keygen', '-q', '-t', 'ed25519',
                 '-N', '', '-C', 'telegram-forwarding', '-f', str(key)])
        if key.stat().st_uid != u.pw_uid or key.stat().st_mode & 0o077:
            raise ValueError('Private key ownership or permissions are unsafe')
    return keydir


def ssh_match(user, peer, key):
    return f'''Match User {user}
    AllowUsers {user}@{peer}
    AuthorizedKeysFile {key}
    AuthenticationMethods publickey
    PubkeyAuthentication yes
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    AllowTcpForwarding local
    AllowStreamLocalForwarding no
    DisableForwarding no
    PermitOpen api.telegram.org:443
    PermitListen none
    AllowAgentForwarding no
    X11Forwarding no
    PermitTTY no
    MaxSessions 0
Match all
'''


def configure_sshd(user, peer, pub):
    safe_dir(CONF)
    auth = CONF / ('authorized_keys_' + user)
    # Dedicated per-user files preserve other tunnel accounts and global SSH policy.
    dropin = DROPIN.with_name(DROPIN.stem + '-' + user + '.conf')
    previous = {}
    for path in (auth, dropin):
        if path.is_symlink() or (path.exists() and (not path.is_file() or path.stat().st_nlink != 1)):
            raise ValueError('Unsafe SSH configuration file')
        previous[path] = (path.read_text(), path.stat().st_mode & 0o777) if path.exists() else None
    try:
        write(auth, f'restrict,port-forwarding,from="{peer}",permitopen="api.telegram.org:443" {pub}\n')
        write(dropin, ssh_match(user, peer, auth))
        run(['sshd', '-t'])
        effective = run(['sshd', '-T', '-C', f'user={user},host=telegram-node,addr={peer}']).stdout
        fields = {}
        for line in effective.splitlines():
            k, _, v = line.partition(' ')
            fields.setdefault(k, []).append(v)
        expected = {'allowusers': [f'{user}@{peer}'], 'authenticationmethods': ['publickey'],
                    'pubkeyauthentication': ['yes'], 'passwordauthentication': ['no'],
                    'kbdinteractiveauthentication': ['no'], 'allowtcpforwarding': ['local'],
                    'allowstreamlocalforwarding': ['no'], 'disableforwarding': ['no'],
                    'permitopen': ['api.telegram.org:443'], 'permitlisten': ['none'],
                    'maxsessions': ['0'], 'authorizedkeysfile': [str(auth)]}
        if any(fields.get(k) != v for k, v in expected.items()):
            raise ValueError('An earlier SSH Match/Include conflicts with the tunnel; previous SSH settings restored')
        for service in ('ssh', 'sshd'):
            if run(['systemctl', 'is-active', '--quiet', service], check=False).returncode == 0:
                run(['systemctl', 'reload', service])
                break
        else:
            raise ValueError('SSH daemon must already be running')
    except Exception:
        for path, old in previous.items():
            if old is None:
                path.unlink(missing_ok=True)
            else:
                write(path, old[0], old[1])
        raise


def ssh_client(name, hostname, number, remote_user, key, listen_port):
    return f'''Host {name}
    HostName {hostname}
    Port {number}
    User {remote_user}
    HostKeyAlias {name}
    UserKnownHostsFile {CONF}/known_hosts_{name}
    StrictHostKeyChecking yes
    IdentityFile {key}
    IdentitiesOnly yes
    BatchMode yes
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    ConnectTimeout 10
    ServerAliveInterval 15
    ServerAliveCountMax 3
    ExitOnForwardFailure yes
    ForwardAgent no
    RequestTTY no
    DynamicForward 127.0.0.1:{listen_port}
'''


def service(command, after='', wants=''):
    return f'''[Unit]
Description=Restricted Telegram forwarding
After=network-online.target docker.service ssh.service vpnbot-telegram-guard.service {after}
Wants=network-online.target {wants}
Requires=vpnbot-telegram-guard.service
StartLimitIntervalSec=0
[Service]
User={USER}
Group={USER}
ExecStart={command}
Restart=always
RestartSec=3
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes
LockPersonality=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
CapabilityBoundingSet=
MemoryMax=64M
TasksMax=32
UMask=0077
[Install]
WantedBy=multi-user.target
'''


def node(args):
    if not re.fullmatch(r'/[A-Za-z0-9_/-]+', args.bot_dir) or '..' in Path(args.bot_dir).parts:
        raise ValueError('Use an absolute VPNBot directory without spaces or ..')
    for command in ('ssh', 'sshd', 'nft', 'curl', 'haproxy', 'systemctl', 'runuser', 'useradd'):
        if not shutil.which(command):
            raise ValueError('Install openssh-client, openssh-server, nftables, curl and haproxy first')
    pinned = public_key(args.host_key_file)
    if args.ipv6_fallback:
        if not Path('/proc/net/if_inet6').exists():
            raise ValueError('IPv6 is disabled in the kernel; do not request IPv6 fallback')
        local_host_key = public_key('/etc/ssh/ssh_host_ed25519_key.pub')
    keys = prepare_key()
    safe_dir(CONF)
    write(CONF / 'known_hosts_telegram-relay', 'telegram-relay ' + pinned + '\n')
    write(CONF / 'relay_ssh_config', ssh_client('telegram-relay', args.relay_host, args.relay_port,
                                              args.relay_user, keys / 'id_ed25519_relay', 10892))
    write(UNIT / 'vpnbot-telegram-relay.service', service(f'/usr/bin/ssh -F {CONF}/relay_ssh_config -N telegram-relay'))
    paths = ['vpnbot-telegram-relay.service']
    if args.ipv6_fallback:
        configure_sshd(USER, '127.0.0.1', public_key(keys / 'id_ed25519_local.pub'))
        write(CONF / 'known_hosts_telegram-local', 'telegram-local ' + local_host_key + '\n')
        write(CONF / 'local_ssh_config', ssh_client('telegram-local', '127.0.0.1', args.local_ssh_port,
                                                  USER, keys / 'id_ed25519_local', 10891))
        write(UNIT / 'vpnbot-telegram-local.service', service(f'/usr/bin/ssh -F {CONF}/local_ssh_config -N telegram-local'))
        paths.append('vpnbot-telegram-local.service')
    else:
        run(['systemctl', 'disable', '--now', 'vpnbot-telegram-local.service'], check=False)
    write(CONF / 'guard.nft', '''add table inet vpnbot_telegram
add chain inet vpnbot_telegram input { type filter hook input priority -10; policy accept; }
flush chain inet vpnbot_telegram input
add rule inet vpnbot_telegram input iifname "br-vpnbot0" ip saddr { 10.10.0.7, 10.10.0.15 } ip daddr 10.10.0.1 tcp dport 10890 counter accept
add rule inet vpnbot_telegram input tcp dport 10890 counter drop
''')
    write(UNIT / 'vpnbot-telegram-guard.service', f'''[Unit]
Description=Restrict the Telegram SOCKS listener to VPNBot application containers
After=network-pre.target nftables.service
Before=vpnbot-telegram-proxy.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/nft -f {CONF}/guard.nft
[Install]
WantedBy=multi-user.target
''')
    write(CONF / 'check-endpoint', '''#!/bin/sh
case "$3:$4" in 127.0.0.1:10891|127.0.0.1:10892) ;; *) exit 1;; esac
code=$(/usr/bin/curl --silent --output /dev/null --proxy "socks5h://$3:$4" --connect-timeout 3 --max-time 5 --write-out '%{http_code}' https://api.telegram.org) || exit 1
[ "$code" = 302 ] || [ "$code" = 200 ]
''', 0o755)
    config = f'''global
    external-check
    insecure-fork-wanted
    maxconn 64
defaults
    mode tcp
    timeout connect 5s
    timeout client 90s
    timeout server 90s
    timeout check 6s
frontend telegram
    bind 10.10.0.1:10890
    default_backend telegram_paths
backend telegram_paths
    option external-check
    external-check path /usr/bin:/bin
    external-check command {CONF}/check-endpoint
    default-server inter 8s fastinter 2s downinter 8s fall 2 rise 2 on-marked-down shutdown-sessions
    server relay 127.0.0.1:10892 check
'''
    if args.ipv6_fallback:
        config += '    server local 127.0.0.1:10891 check backup\n'
    write(CONF / 'haproxy.cfg', config)
    run(['haproxy', '-c', '-f', str(CONF / 'haproxy.cfg')])
    write(UNIT / 'vpnbot-telegram-proxy.service', service(
        f'/usr/sbin/haproxy -db -f {CONF}/haproxy.cfg', ' '.join(paths), ' '.join(paths)))
    run(['nft', '-c', '-f', str(CONF / 'guard.nft')])
    run(['systemctl', 'daemon-reload'])
    run(['systemctl', 'enable', 'vpnbot-telegram-guard.service', 'vpnbot-telegram-proxy.service', *paths])
    run(['systemctl', 'restart', 'vpnbot-telegram-guard.service', *paths, 'vpnbot-telegram-proxy.service'])
    helper = Path(__file__).resolve()
    write(UNIT / 'vpnbot-telegram-app.service', f'''[Unit]
Description=Attach Telegram tunnel after VPNBot installation
After=docker.service vpnbot-telegram-proxy.service
[Service]
Type=oneshot
ExecStart=/usr/bin/python3 {helper} attach-bot --wait --directory {args.bot_dir}
TimeoutStartSec=5min
UMask=0077
''')
    write(UNIT / 'vpnbot-telegram-app.timer', '''[Unit]
Description=Wait for the first VPNBot installation to configure Telegram
[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
[Install]
WantedBy=timers.target
''')
    run(['systemctl', 'daemon-reload'])
    run(['systemctl', 'enable', '--now', 'vpnbot-telegram-app.timer'])
    print('Tunnel services installed. Run check after authorizing the node public key on the relay.')
    print('VPNBot override.env: TELEGRAM_PROXY=socks5h://10.10.0.1:10890')
    print('For the full VPNBot use its matching PL, GE or RelayVPNBot firewall profile: only PHP/service may use this listener.')
    print('The minimal noda-nuxt-youtube profile is for node mode, which does not need Telegram or this proxy.')


def bot_proxy_active(base):
    running = run(['docker', 'compose', 'ps', '--quiet', '--status', 'running', 'php', 'service'],
                  cwd=base, check=False)
    containers = running.stdout.split()
    if running.returncode or len(containers) != 2 or not all(re.fullmatch(r'[a-f0-9]{12,64}', c) for c in containers):
        return False
    # Compare inside each container: never retrieve its environment or a token.
    return all(run(['docker', 'exec', container, 'sh', '-c',
                    'test "$TELEGRAM_PROXY" = "socks5h://10.10.0.1:10890"'],
                   check=False).returncode == 0 for container in containers)


def attach_bot(directory, wait=False):
    base = Path(directory)
    if base.exists():
        safe_dir(base)
    if wait:
        if not (base / 'scripts/protocol_modules.py').is_file() or not shutil.which('docker'):
            return
        running = run(['docker', 'compose', 'ps', '--services', '--status', 'running'], cwd=base, check=False)
        if running.returncode or not {'php', 'service'}.issubset(running.stdout.split()):
            return
    if not base.is_absolute() or base.is_symlink() or not (base / 'scripts/protocol_modules.py').is_file():
        raise ValueError('VPNBot is not installed in this directory')
    if base.stat().st_uid != 0 or base.stat().st_mode & 0o022:
        raise ValueError('VPNBot directory must be root-owned and not writable by others')
    target = base / 'override.env'
    if target.is_symlink():
        raise ValueError('Unsafe VPNBot override file')
    # No app/config.php or Telegram token is opened. Preserve unrelated overrides.
    before = target.read_text() if target.exists() else ''
    lines = [line for line in before.splitlines() if not re.match(r'^\s*(?:export\s+)?TELEGRAM_PROXY=', line)]
    after = '\n'.join(lines) + '\nTELEGRAM_PROXY=socks5h://10.10.0.1:10890\n'
    if before == after and bot_proxy_active(base):
        print('VPNBot proxy already configured')
        if wait:
            run(['systemctl', 'disable', '--now', 'vpnbot-telegram-app.timer'])
        return
    write(target, after, 0o600)
    env = os.environ.copy()
    env['IP'] = run(['hostname', '-I']).stdout.split()[0]
    env['VER'] = run(['git', 'describe', '--tags', '--always'], cwd=base).stdout.strip()
    try:
        run(['python3', 'scripts/protocol_modules.py', 'compose', 'up', '-d', '--no-deps',
             '--force-recreate', 'php', 'service'], cwd=base, env=env)
        if not bot_proxy_active(base):
            raise RuntimeError('VPNBot containers did not apply the Telegram proxy')
    except Exception:
        write(target, before, 0o600)
        run(['python3', 'scripts/protocol_modules.py', 'compose', 'up', '-d', '--no-deps',
             '--force-recreate', 'php', 'service'], cwd=base, env=env, check=False)
        raise
    if wait:
        run(['systemctl', 'disable', '--now', 'vpnbot-telegram-app.timer'])
    print('VPNBot PHP/service recreated with the private Telegram proxy')


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest='action', required=True)
    sub.add_parser('key', help='Create node identities and print only the relay PUBLIC key')
    r = sub.add_parser('relay', help='Authorize one node on the relay; never changes its firewall')
    r.add_argument('--source', required=True, type=source)
    r.add_argument('--public-key-file', required=True)
    r.add_argument('--user', type=username, default='vpb-tg-relay')
    n = sub.add_parser('node', help='Install the node tunnel and health-checked optional backup')
    n.add_argument('--relay-host', required=True, type=host)
    n.add_argument('--relay-port', default=22, type=port)
    n.add_argument('--relay-user', default='vpb-tg-relay', type=username)
    n.add_argument('--host-key-file', required=True)
    n.add_argument('--ipv6-fallback', action='store_true')
    n.add_argument('--local-ssh-port', default=22, type=port)
    n.add_argument('--bot-dir', default='/root/vpnbot')
    a = sub.add_parser('attach-bot', help='Enable the proxy on an installed VPNBot, without reading its token')
    a.add_argument('--directory', default='/root/vpnbot')
    a.add_argument('--wait', action='store_true')
    sub.add_parser('check', help='Probe HTTPS through each path, without a Telegram token')
    return p


def main():
    args = parser().parse_args()
    if os.geteuid() != 0:
        raise ValueError('Run as root')
    os.umask(0o077)
    lock = os.open('/run/lock/system-setup-telegram.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if args.action == 'key':
            print(public_key(prepare_key() / 'id_ed25519_relay.pub'))
        elif args.action == 'relay':
            pub = public_key(args.public_key_file)
            account(args.user, '/nonexistent')
            configure_sshd(args.user, args.source, pub)
            print('Relay configured: key-only forwarding to api.telegram.org:443; shell and other destinations denied.')
            print('Allow the node source address in the relay firewall before connecting.')
        elif args.action == 'node':
            node(args)
        elif args.action == 'attach-bot':
            attach_bot(args.directory, args.wait)
        else:
            result = {}
            for name, number in [('relay', 10892), ('local', 10891)]:
                p = run(['curl', '--silent', '--output', '/dev/null', '--proxy', f'socks5h://127.0.0.1:{number}',
                         '--connect-timeout', '3', '--max-time', '6', '--write-out', '%{http_code}', 'https://api.telegram.org'], check=False)
                result[name] = p.returncode == 0 and p.stdout in ('200', '302')
            print(json.dumps(result))
            return 0 if any(result.values()) else 1
    finally:
        os.close(lock)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, RuntimeError, OSError) as exc:
        # No traceback or command output: never reveal configuration or key data.
        print('Telegram tunnel setup failed: ' + str(exc), file=sys.stderr)
        sys.exit(1)
