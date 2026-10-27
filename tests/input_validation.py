#!/usr/bin/env python3
"""Exercise interactive input with synthetic answers, without changing the host."""
import ipaddress
from pathlib import Path
import re
import random
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'system-setup.sh').read_text()
INPUT_HELPERS = SOURCE.split('# Invalid answers are recoverable:', 1)[1].split('\nreport_setup_result()', 1)[0]
INPUT_HELPERS = '# Invalid answers are recoverable:' + INPUT_HELPERS


def function(name, source=SOURCE):
    return re.search(rf'(?ms)^{name}\(\) \{{\n.*?^\}}$', source)[0] + '\n'


BASE = '''
print_error() { printf 'ERROR: %s\\n' "$1" >&2; }
print_warning() { printf 'WARNING: %s\\n' "$1" >&2; }
print_message() { :; }
is_yes() { [ "$1" = y ] || [ "$1" = Y ]; }
'''


class InputValidation(unittest.TestCase):
    def shell(self, body, answers='', args=()):
        return subprocess.run(['bash', '-c', 'set -o pipefail\n' + BASE +
                               function('prompt_read') + INPUT_HELPERS + body,
                               'test', *args], input=answers, text=True,
                              capture_output=True, timeout=10)

    def assert_validity(self, validator, valid, invalid, extra=''):
        for expected, values in ((0, valid), (1, invalid)):
            for value in values:
                with self.subTest(validator=validator, value=value):
                    result = self.shell(f'{validator} "$1" {extra}', args=(value,))
                    self.assertEqual(result.returncode, expected, result.stderr)
                    self.assertEqual(result.stdout + result.stderr, '')

    def test_every_yes_no_call_retries_and_keeps_its_default(self):
        calls = re.findall(r'^\s*(prompt_yes_no (\w+) "[^"\n]*" ([yn]))$', SOURCE, re.M)
        self.assertGreater(len(calls), 65)
        for call, var, default in calls:
            for answer, expected in ((' YES ', 'y'), ('нет', 'n'), ('', default)):
                with self.subTest(var=var, default=default, answer=answer):
                    result = self.shell(call + f'\nread -r next\nprintf "RESULT:%s|%s" "${var}" "$next"',
                                        f'wrong-answer\n{answer}\nNEXT\n')
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout, f'RESULT:{expected}|NEXT')
                    self.assertEqual(result.stderr.count('Invalid input.'), 1)
                    self.assertNotIn('wrong-answer', result.stderr)
                    self.assertNotIn('ERROR:', result.stderr)

    def test_yes_no_aliases(self):
        for answer, expected in [('y', 'y'), ('Yes', 'y'), ('ДА', 'y'), ('д', 'y'),
                                 ('n', 'n'), ('NO', 'n'), ('НЕТ', 'n'), ('н', 'n')]:
            result = self.shell('prompt_yes_no answer "Choice: " n\nprintf "%s" "$answer"', answer+'\n')
            self.assertEqual(result.stdout, expected)

    def test_eof_cancels_all_prompt_types(self):
        for body in ('prompt_yes_no value "Choice: " n',
                     'prompt_value value "Number: " 1 valid_choice "Use 1 or 2." 1 2',
                     'prompt_secret value "Password: "', 'prompt_cron_tasks 2'):
            for answers in ('', '\n' if 'prompt_secret' in body else 'invalid\n'):
                result = self.shell(body+'\nprintf "DONE"', answers)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('DONE', result.stdout)

    def test_numeric_menus_require_exact_choices(self):
        self.assert_validity('valid_choice', ['1', '2'], ['', '01', '0', '-1', '3', '1 2', '1;exit'], '1 2')
        result = self.shell('prompt_value value "Mode: " 2 valid_choice "Choose 1 or 2." 1 2\nprintf "%s" "$value"', '5\nword\n\n')
        self.assertEqual(result.stdout, '2')
        self.assertEqual(result.stderr.count('Invalid input.'), 2)

    def test_port_bounds_and_overflow(self):
        self.assert_validity('valid_uint', ['1', '22', '08', '65535'],
                             ['', '0', '65536', '-22', '1.2', '1e3', '1+1', '9'*100, '$(exit 9)'], '1 65535')
        self.assert_validity('valid_ports', ['', '80', '80/tcp, 53/udp,65535'],
                             ['0', '65536', '1,0', '80,,443', '80,', ',80', '80, ,443', '80/icmp', '80 443', '*', '--help'])

    def test_usernames_and_existing_accounts(self):
        self.assert_validity('valid_new_username', ['boss', '_agent', 'test-2', 'svc$'],
                             ['', '1user', 'Root', '-x', 'x y', 'x\ty', 'a'*33, 'a/b'])
        body = '''
CREATE_USER=y NEW_USERNAME=planned
id() { [ "${@: -1}" = root ]; }
'''
        for answer, code in [('root planned', 0), ('', 0), ('missing', 1), ('root missing', 1), ('root\nPermitRootLogin yes', 1)]:
            result = self.shell(body+'valid_allow_users "$1"', args=(answer,))
            self.assertEqual(result.returncode, code)

    def test_root_login_choices(self):
        self.assert_validity('valid_root_login', ['y', 'YES', 'p', 'prohibit-password', 'no'], ['', 'true', '0', 'perhaps'])

    def test_passwords_remain_hidden_and_spaces_are_preserved(self):
        result = self.shell('set -x\nprompt_secret secret "Password: "\n[ "$secret" = " fixture with spaces " ]',
                            '\nfixture\tbad\n fixture with spaces \n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr.count('Invalid input.'), 2)
        self.assertNotIn('fixture', result.stdout + result.stderr)

    def test_public_key_blob_is_checked(self):
        with tempfile.TemporaryDirectory() as temp:
            key = Path(temp) / 'fixture'
            subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(key)], check=True)
            public = key.with_suffix('.pub').read_text().strip()
            self.assert_validity('valid_public_key', [public, public.replace(' ', '\t')],
                                 ['', 'ssh-ed25519 AAAA invalid', '-----BEGIN PRIVATE KEY-----', public+'\n'+public])
            self.assert_validity('valid_public_key', [''], [public, 'sk-ssh-ed25519@openssh.com AAAA'], 'fido')

    def test_venv_path_formats(self):
        self.assert_validity('valid_venv_path', ['/root/skripts', '/tmp/a path/venv'],
                             ['', '/', 'relative', '~/venv', '/tmp/../etc', '/tmp/./v', '/tmp//v', '/tmp/v/', '/tmp/v\ncmd', '/dev/null'])

    def test_dns_ipv4_ipv6(self):
        valid = ['1.1.1.1', '127.0.0.1', '::', '::1', '2001:db8::1', '1:2:3:4:5:6:7:8',
                 '::ffff:192.0.2.1', 'fe80::1%eth0']
        invalid = ['', '256.1.1.1', '1.2.3', '01.2.3.4', 'https://1.1.1.1', 'dns.example',
                   ':1::2', '1::2:', '1::2::3', '1:2:3:4:5:6:7', '1:2:3:4:5:6:7:8:9',
                   '1:2:3:4:5:6:7:8::', ':::1', '::gg', '::ffff:999.0.0.1', '::1%a%b', '::1%']
        self.assert_validity('valid_dns_ip', valid, invalid)
        # Generated valid addresses cover compressed/full spellings without DNS/network calls.
        for number in (0, 1, (1<<128)-1, int(ipaddress.IPv6Address('2001:db8:123:456::ff'))):
            address = ipaddress.IPv6Address(number)
            self.assert_validity('valid_dns_ip', [address.compressed, address.exploded], [])

    def test_ntp_names(self):
        self.assert_validity('valid_ntp_host', ['pool.ntp.org', 'time.example.', 'localhost', '192.0.2.1'],
                             ['', 'a..b', '.abc', '-host', 'host-', 'a'*64+'.test', '256.0.0.1', 'http://ntp.test', 'ntp.test:123'])

    def test_packages_and_nginx_repositories(self):
        self.assert_validity('valid_packages', ['', 'nginx,nginx-module-njs', 'nginx:amd64=1.2.3-1~test'],
                             ['--allow-unauthenticated', './pkg.deb', 'nginx*', 'nginx;id', 'nginx $(id)'])
        self.assert_validity('valid_packages', ['nginx'], ['', ', ,'], 'required')
        for org, myguard, modules, allowed in [('y', 'n', 'n', '127'), ('y', 'n', 'y', '12347'), ('n', 'y', 'n', '5678')]:
            for choice in '123456789':
                result = self.shell(f'ADD_NGINX_ORG={org} ADD_NGINX_MYGUARD={myguard} ADD_NGINX_MODULES={modules}\nvalid_nginx_preset "$1"', args=(choice,))
                self.assertEqual(result.returncode, 0 if choice in allowed else 1)

    def test_nft_profile_retry_without_array_evaluation(self):
        with tempfile.TemporaryDirectory() as temp:
            marker = str(Path(temp) / 'executed')
            body = '''
NFT_PROFILES_COUNT=5 NFT_DEFAULT_PROFILE=1
NFT_PROFILE_NAMES=([1]=pl [2]=ge [3]=relay-net0 [4]=relay-eth0 [5]=fr)
prompt_value profile "Profile: " 1 valid_nft_profile "Select profile number."
printf '%s' "${NFT_PROFILE_NAMES[$profile]}"
'''
            result = self.shell(body, f'pl\n6\n0\n08\na[$(touch {marker})]\n2\n')
            self.assertEqual(result.stdout, 'ge')
            self.assertEqual(result.stderr.count('Invalid input.'), 5)
            self.assertFalse(Path(marker).exists())

    def test_nft_menu_flow_repeats_invalid_answers(self):
        section = SOURCE.split('        # Ask about nftables config profile\n', 1)[1].split('\n    else\n        INSTALL_NFTABLES_CONF="n"', 1)[0]
        body = '''
RESTORE_OPT_VAULT=y NFT_PROFILES_COUNT=2 NFT_DEFAULT_PROFILE=1
NFT_PROFILE_NAMES=([1]=pl [2]=ge)
NFT_PROFILE_DESCRIPTIONS=([1]=PL [2]=GE)
NFT_PROFILE_CONFIGS=([1]=pl.conf [2]=ge.conf)
NFT_PROFILE_LOGSCRIPTS=([1]=pl.sh [2]=ge.sh)
'''+section+'\nprintf "RESULT:%s|%s|%s" "$INSTALL_NFTABLES_CONF" "$NFTABLES_PROFILE" "$INSTALL_NFTABLES_LOGGING"'
        result = self.shell(body, '1\nyes\npl\n9\n1\nwat\nyes\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('RESULT:y|pl|y', result.stdout)
        self.assertEqual(result.stderr.count('Invalid input.'), 4)
        result = self.shell(body, 'n\n')
        self.assertIn('RESULT:n||n', result.stdout)

    def test_cron_validation_and_pasted_block_retry(self):
        self.assert_validity('valid_cron_line', ['', '# comment', 'MAILTO=""', '@reboot sh -c "echo ok"',
                    '*/5 0-23 * jan,dec mon-fri /bin/true', '0\t3\t*\t*\t6\t/bin/true'],
                    ['@unknown command', '@reboot', '60 * * * * command', '*/0 * * * * command',
                     '0 24 * * * command', '* * 0 * * command', '* * * 13 * command', '* * * * 8 command',
                     '* * * * *', 'one two three four five command', '* * * * 5-1 command',
                     '* * * janjan * command', '* * * janfeb * command', '* * * * sunsun command'])
        body='prompt_cron_tasks 2\nread -r next\nprintf "RESULT:%s|%s" "$CRONTAB_TASKS" "$next"'
        result = self.shell(body, 'invalid\n@reboot echo first\nEND\n@reboot echo good\nEND\nNEXT\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, 'RESULT:@reboot echo good|NEXT')
        self.assertNotIn('first', result.stdout+result.stderr)
        result = self.shell('prompt_cron_tasks 1', 'invalid\n')
        self.assertNotEqual(result.returncode, 0)
        result = self.shell('prompt_cron_tasks 1', '@reboot /bin/true\n')
        self.assertEqual(result.returncode, 0)

    def test_ntp_partial_invalid_selection_is_not_applied(self):
        body = function('timesync_choose_servers') + '''
TIMESYNC_MAX_ADDRESSES=4 TIMESYNC_RECOMMENDED='one.test two.test'
TIMESYNC_RESULTS=('one.test 3 3 1 1 0' 'two.test 3 3 2 1 0')
timesync_probe_servers() { :; }
timesync_print_results() { :; }
timesync_choose_servers
printf '%s' "$TIMESYNC_SERVERS"
'''
        result = self.shell(body, '1 wrong\n08\n*\n2\n')
        self.assertEqual(result.stdout, 'two.test')
        self.assertEqual(result.stderr.count('Invalid input.'), 3)

    def test_generated_ipv6_matches_standard_parser(self):
        rng = random.Random(42)
        values = {'::', ':', ':::'}
        for _ in range(150):
            value = ipaddress.IPv6Address(rng.getrandbits(128)).compressed
            index = rng.randrange(len(value))
            values.update((value, value[:index]+':'+value[index:],
                           value[:index]+value[index+1:], value+':'))
        values = sorted(values)
        result = self.shell('while IFS= read -r address; do valid_dns_ip "$address"; printf "%s\\n" "$?"; done',
                            '\n'.join(values)+'\n')
        statuses = result.stdout.splitlines()
        self.assertEqual(len(statuses), len(values))
        for value, status in zip(values, statuses):
            try:
                ipaddress.ip_address(value)
                valid = True
            except ValueError:
                valid = False
            self.assertEqual(status == '0', valid, value)

    def test_whole_configuration_wizard_with_bad_answers_first(self):
        # Execute the real configuration section only; no installation, services or network.
        section = SOURCE.split('# INTERACTIVE CONFIGURATION SELECTION', 1)[1].split('# Confirm settings', 1)[0]
        helpers = ''.join(function(name) for name in ('prompt_setup_user', 'configure_tmux_choice', 'configure_ghx_choice'))
        body = r''' 
INTERACTIVE=$1 OS=debian VERSION=13 VERSION_CODENAME=trixie
FIREWALL_FIXTURE=$2
NEW_USERNAME='' SUDO_USER=root
NFT_PROFILES_COUNT=2 NFT_DEFAULT_PROFILE=1
NFT_PROFILE_NAMES=([1]=pl [2]=ge)
NFT_PROFILE_DESCRIPTIONS=([1]=PL [2]=GE)
NFT_PROFILE_CONFIGS=([1]=pl.conf [2]=ge.conf)
NFT_PROFILE_LOGSCRIPTS=([1]=pl.sh [2]=ge.sh)
declare -A attempts=()
print_header() { :; }
ss() { :; }
id() { [ "${@: -1}" = root ]; }
dpkg-query() { return 1; }
nginx() { :; }
timesync_detect_service() { TIMESYNC_SERVICE=none; }
timesync_status_text() { :; }
timesync_choose_servers() { TIMESYNC_SERVERS=time.test; }
# Keep the actual prompt/validation helpers, supply answers by field instead of typing.
prompt_read() {
    local target="${@: -1}" key reply
    key=${__input_target:-$target}
    attempts[$key]=$(( ${attempts[$key]:-0} + 1 ))
    if [ "${attempts[$key]}" -eq 1 ]; then
        reply=wrong
        [[ "$key" = NEW_USERNAME ]] && reply='invalid name'
        [[ "$key" = NGINX_CUSTOM_PKGS ]] && reply='--invalid-option'
        [[ "$target" = __input_secret ]] && reply=''
    else
        case "$key" in
            ROOT_PASSWORD|ROOT_PASSWORD_CONFIRM|NEW_USER_PASSWORD|NEW_USER_PASSWORD_CONFIRM|OPT_VAULT_PASSWORD|UFW_CUSTOM_RULES_PASSWORD) reply='synthetic fixture' ;;
            NEW_USERNAME|TMUX_USER|GHX_USER|YUBIKEY_SSH_USER|SSH_ALLOW_USERS) reply=planned ;;
            CONFIGURE_USER_SSH_KEY|ADD_NGINX_MYGUARD|REMOVE_NGINX) reply=n ;;
            CRONTAB_MODE) reply=3 ;;
            SSH_ROOT_LOGIN) reply=prohibit-password ;;
            SSH_PORT|UFW_SSH_PORT) reply=7384 ;;
            YUBIKEY_SSH_PUBLIC_KEY) reply='' ;;
            VENV_PATH) reply=/root/fixture-venv ;;
            RESOLVED_DNS) reply=2001:db8::1 ;;
            FIREWALL_BACKEND_CHOICE) reply=$FIREWALL_FIXTURE ;;
            UFW_RULES_VERSION) reply=6 ;;
            UFW_INSTALL_SOURCE) reply=1 ;;
            NFTABLES_PROFILE_NUM) reply=1 ;;
            SYSCTL_MODE|SWAP_MODE) reply=2 ;;
            NGINX_INSTALL_VARIANT) reply=3 ;;
            NGINX_CUSTOM_PKGS) reply=nginx-module-njs ;;
            CUSTOM_PORTS) reply='80/tcp,53/udp' ;;
            *) reply=yes ;;
        esac
    fi
    # Avoid a perpetual error for FIDO: invalid text first, then explicitly empty.
    printf -v "$target" '%s' "$reply"
}
''' + helpers + section + r'''
printf 'RESULT:%s|%s|%s|%s|%s|%s|%s|%s|%s' "$FIREWALL_BACKEND" "$NFTABLES_PROFILE" "$INSTALL_NFTABLES_LOGGING" "$SSH_PORT" "$SSH_ALLOW_USERS" "$SSH_ROOT_LOGIN" "$SWAP_INTERACTIVE" "$NGINX_INSTALL_VARIANT" "$CREATE_USER"
'''
        for mode, backend in [('1', 'nftables'), ('2', 'ufw'), ('3', 'none')]:
            result = self.shell(body, args=('true', mode))
            self.assertEqual(result.returncode, 0, result.stderr)
            profile = 'pl|y' if mode == '1' else '|n'
            self.assertIn(f'RESULT:{backend}|{profile}|7384|planned|prohibit-password|true|3|y', result.stdout)
            self.assertNotIn('ERROR:', result.stderr)
            self.assertGreater(result.stderr.count('Invalid input.'), 50)
        result = self.shell(body, args=('false', '2'))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('Invalid input.', result.stderr)

    def test_no_unvalidated_direct_reads_remain(self):
        direct = re.findall(r'^\s*prompt_read .+$', SOURCE, re.M)
        self.assertEqual(len(direct), 4)  # three helpers plus the validated NTP selection loop
        self.assertNotRegex(SOURCE, r'(?m)^\s*read\s+[^\n]*-p ')

    def test_watch_menu_retries_and_eof_never_deletes(self):
        source=(ROOT/'install-nft-docker-watch.sh').read_text()
        body='''
log_info() { :; }
log_warn() { printf 'RETRY\\n' >&2; }
log_error() { printf 'ERROR\\n' >&2; }
print_header() { :; }
do_uninstall() { printf 'DELETED\\n'; }
do_status() { printf 'STATUS\\n'; }
'''+function('show_menu', source)+'\nshow_menu'
        for answers, expected, retries in [('bad\n4\n', 'STATUS', 1), ('3\nmaybe\nYES\n', 'DELETED', 1),
                                           ('3\nn\n', '', 0), ('3\n', '', 0)]:
            result=self.shell(body, answers)
            if expected: self.assertIn(expected, result.stdout)
            else: self.assertNotIn('DELETED', result.stdout)
            self.assertEqual(result.stderr.count('RETRY'), retries)
            self.assertEqual(result.returncode, 1 if answers == '3\n' else 0)


if __name__ == '__main__':
    unittest.main()
