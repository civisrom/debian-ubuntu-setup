import copy
import importlib.util
import json
import os
from pathlib import Path
import types
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT/'scripts/node_host.py'
if not SOURCE.exists():
    SOURCE = ROOT/'config/nft-node-host.py'
spec = importlib.util.spec_from_file_location('node_host_fixture', SOURCE)
host = importlib.util.module_from_spec(spec)
spec.loader.exec_module(host)

PROFILE = '''# VPNBOT_MANAGED_NODE_HOST
define WAN = "ens3"
define PUBLIC_IP = 11.77.0.9
define NODE_SSH_PORTS = { 22 }
define SERVER_SSH_PORTS = { 22 }
flush ruleset
table ip filter {
 set node4_sources { type ipv4_addr; elements = { 11.77.0.2 }; }
 set node4_admins { type ipv4_addr; elements = { 11.77.0.3 }; }
 set node4_ssh { type ipv4_addr; flags interval; elements = { 11.77.0.128/25 }; }
 chain ssh_log { accept; }
 chain input { type filter hook input priority 0; policy drop;
  iifname $WAN ip saddr @node4_admins tcp dport $NODE_SSH_PORTS ct state new jump ssh_log
  iifname $WAN ip saddr 11.77.1.0/24 tcp dport $NODE_SSH_PORTS accept
 }
}
table ip6 filter {
 set node6_sources { type ipv6_addr; }
 set node6_admins { type ipv6_addr; }
 set node6_ssh { type ipv6_addr; flags interval; }
 set node6_public { type ipv6_addr; }
 set ipv6_routers { type ipv6_addr; elements = { fe80::2 }; }
 chain ssh_log { accept; }
 chain input { type filter hook input priority 0; policy drop;
  iifname $WAN ip6 saddr @node6_admins tcp dport $NODE_SSH_PORTS ct state new jump ssh_log
 }
}
'''
FACTS = dict(interface='eth0.100', public4='11.77.0.4', public6='', ssh_ports=[7384], routers=[])


class NodeHostTest(unittest.TestCase):
    def setUp(self):
        self.env = patch.dict(os.environ, {'SSH_CONNECTION': '11.77.0.3 12000 11.77.0.4 22'})
        self.env.start()
        self.addCleanup(self.env.stop)

    def test_prepare_keeps_current_admin_and_persists_actual_host(self):
        text = host.prepare(PROFILE, FACTS, ['11.77.0.3', '11.77.0.5'])
        self.assertIn('define WAN = "eth0.100"', text)
        self.assertIn('define PUBLIC_IP = 11.77.0.4', text)
        self.assertIn('define SERVER_SSH_PORTS = { 7384 }', text)
        self.assertEqual(host.access(text)['admins'], ['11.77.0.3', '11.77.0.5'])
        self.assertEqual(host.access(text)['sources'], ['11.77.0.2'])
        self.assertEqual(host.access(text)['ssh_networks'], ['11.77.0.128/25'])
        self.assertIn('elements = { fe80::2 };', text)
        self.assertEqual(text, host.prepare(text, FACTS, ['11.77.0.3', '11.77.0.5']))

    def test_management_port_does_not_open_the_existing_asn(self):
        text = host.prepare(PROFILE, FACTS, ['11.77.0.3'])
        self.assertIn('define NODE_SSH_PORTS = { 22 }', text)
        self.assertIn('ip saddr 11.77.1.0/24 tcp dport $NODE_SSH_PORTS accept', text)
        for v in (4, 6):
            self.assertIn('@node'+str(v)+'_admins tcp dport $SERVER_SSH_PORTS', text)
        self.assertEqual(text.count('policy drop;'), PROFILE.count('policy drop;'))

    def test_no_current_source_or_public_address_refuses_preparation(self):
        with patch.dict(os.environ, {'SSH_CONNECTION': '11.77.0.8 12345 11.77.0.4 22'}):
            with self.assertRaises(ValueError):
                host.prepare(PROFILE, FACTS, ['11.77.0.5'])
        with self.assertRaises(ValueError):
            host.prepare(PROFILE, FACTS | {'public4': ''}, ['11.77.0.3'])

    def test_console_requires_an_explicit_admin(self):
        empty = PROFILE.replace(' elements = { 11.77.0.3 };', '')
        with patch.dict(os.environ, {'SSH_CONNECTION': ''}):
            with self.assertRaises(ValueError):
                host.prepare(empty, FACTS, [])
            self.assertIn('11.77.0.5', host.prepare(empty, FACTS, ['11.77.0.5']))

    def test_invalid_and_ambiguous_sets_fail_before_preparation(self):
        broken = PROFILE.replace('type ipv4_addr; flags interval; elements = { 11.77.0.128/25 };', '11.77.0.3, 11.77.0.5')
        for text in (broken, PROFILE+'\nset node4_admins { type ipv4_addr; }', PROFILE.replace('11.77.0.3', '127.0.0.1'), PROFILE.replace('11.77.0.128/25', '0.0.0.0/0')):
            with self.subTest(text=text), self.assertRaises(ValueError):
                host.prepare(text, FACTS, ['11.77.0.3'])

    def test_defaults_preserve_explicit_acl_and_add_current_ssh_source(self):
        with patch.object(host, 'read_profile', return_value=PROFILE), patch.object(host, 'discover', return_value=copy.deepcopy(FACTS)), patch.dict(os.environ, {'SSH_CONNECTION': '11.77.0.5 12345 11.77.0.4 22'}):
            values = host.defaults()
        self.assertEqual(values['admins'], ['11.77.0.3', '11.77.0.5'])
        self.assertEqual(values['sources'], ['11.77.0.2'])
        self.assertEqual(values['ssh_networks'], ['11.77.0.128/25'])
        self.assertEqual(values['routers'], ['fe80::2'])

    def test_unrelated_profile_does_not_supply_trust(self):
        self.assertEqual(host.access(PROFILE.replace('# VPNBOT_MANAGED_NODE_HOST', '# other')), dict(sources=[], admins=[], ssh_networks=[]))

    def test_manual_network_entry_remains_available_if_discovery_fails(self):
        with patch.object(host, 'read_profile', return_value=PROFILE), patch.object(host, 'discover', side_effect=ValueError('Ambiguous WAN route')), patch.object(host, 'ssh_ports', return_value=[7384]):
            values = host.defaults()
        self.assertFalse(values['network_detected'])
        self.assertEqual(values['interface'], 'ens3')
        self.assertEqual(values['public4'], '11.77.0.9')
        self.assertEqual(values['ssh_ports'], [7384])
        self.assertEqual(values['admins'], ['11.77.0.3'])

    def test_public_validation_rejects_injection_and_non_public(self):
        for value in ('127.0.0.1', '10.0.0.1', '0.0.0.0', '224.0.0.1', '::1', 'fe80::1', 'ff02::1', '2606:4700::1%eth0', '11.77.0.3/32', '11.77.0.3; accept'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                host.public(value)

    def discover(self, v4=True, v6=False, interface6='eth0.100', unstable=None):
        def command(args):
            if args[0] == 'sshd':
                return types.SimpleNamespace(returncode=0, stdout='port 7384\nport 2222\n')
            if 'route' in args:
                version = 4 if '-4' in args else 6
                if not (v4 if version == 4 else v6):
                    return types.SimpleNamespace(returncode=2, stdout='')
                value = dict(dev='eth0.100' if version == 4 else interface6, prefsrc='11.77.0.4' if version == 4 else '2606:4700::4')
                if version == 6:
                    value['gateway'] = 'fe80::1'
                return types.SimpleNamespace(returncode=0, stdout=json.dumps([value]))
            entries = [dict(local='11.77.0.4', family='inet', scope='global'), dict(local='2606:4700::4', family='inet6', scope='global')]
            if unstable:
                for entry in entries:
                    entry.update(unstable)
            return types.SimpleNamespace(returncode=0, stdout=json.dumps([{'addr_info': entries}]))
        with patch.object(host, 'command', side_effect=command):
            return host.discover()

    def test_discover_vlan_and_effective_multiple_ssh_ports(self):
        values = self.discover()
        self.assertEqual(values, FACTS | {'ssh_ports': [2222, 7384]})

    def test_discover_ipv6_only_and_router(self):
        values = self.discover(v4=False, v6=True)
        self.assertEqual(values['public4'], '')
        self.assertEqual(values['public6'], '2606:4700::4')
        self.assertEqual(values['routers'], ['fe80::1'])

    def test_discover_refuses_split_wan_and_unstable_addresses(self):
        with self.assertRaises(ValueError):
            self.discover(v6=True, interface6='eth1')
        for flag in ('tentative', 'dadfailed', 'temporary', 'deprecated'):
            for flags in ({flag: True}, {'flags': [flag]}):
                with self.subTest(flags=flags), self.assertRaises(ValueError):
                    self.discover(unstable=flags)


if __name__ == '__main__':
    unittest.main()
