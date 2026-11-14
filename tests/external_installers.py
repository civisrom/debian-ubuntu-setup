#!/usr/bin/env python3
import os
import hashlib
import io
import tarfile
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

BASE=Path(__file__).resolve().parents[1]
SOURCE=Path(os.environ.get('EXTERNAL_SOURCE',str(BASE/'config/vendor')))

def function(file,name):
    text=(SOURCE/file).read_text()
    match=re.search(r'(?ms)^(?:function )?'+re.escape(name)+r'\(\) \{\n.*?^\}',text)
    if match is None:raise AssertionError(name)
    return match[0]+'\n'

LOGS='''
print_message() { :; }; print_error() { :; }; print_warning() { :; }; print_success() { :; }
log_info() { :; }; log_error() { :; }; log_warn() { :; }; log_warning() { :; }; log_success() { :; }; log_section() { :; }
msg() { printf '%s' "$1"; }; sleep() { :; }
'''

class ExternalTests(unittest.TestCase):
    def test_main_pins_both_motd_and_ufw_variants(self):
        main=(BASE/'system-setup.sh').read_text()
        for variable,names in (
            ('MOTD_SHA256',('motd-debian.sh','motd-ubuntu.sh')),
            ('UFW_RULES_SHA256',('ufw-rules-v4.sh','ufw-rules-v6.sh')),
        ):
            with self.subTest(variable=variable):
                expected=[hashlib.sha256((BASE/'config/vendor'/name).read_bytes()).hexdigest()
                          for name in names]
                actual=re.findall(r'\b'+variable+r'="([a-f0-9]{64})"',main)
                self.assertEqual(actual,expected)
        base='https://raw.githubusercontent.com/civisrom/debian-ubuntu-setup/${SYSTEM_SETUP_REPOSITORY_REF}/config/vendor/'
        self.assertEqual(re.findall(r'\bMOTD_URL="([^"]+)"',main),
                         [base+'motd-debian.sh',base+'motd-ubuntu.sh'])
        self.assertEqual(re.findall(r'\bUFW_REPO_URL="([^"]+)"',main),
                         [base+'ufw-rules-v${UFW_RULES_VERSION}.sh'])

    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
    def bash(self,code,input='',env=None):
        return subprocess.run(['bash','-c',LOGS+code],cwd=self.root,text=True,input=input,capture_output=True,timeout=15,env=dict(os.environ,**(env or {})))
    def test_ufw_padded_rule_is_deleted(self):
        for name in ('ufw-rules-v4.sh','ufw-rules-v6.sh'):
            with self.subTest(name=name):
                result=self.bash(function(name,'safe_delete_rule')+'''
ufw() { if [[ $1 == status ]]; then printf '[ 1] 22/tcp ALLOW IN Anywhere\n'; else touch deleted; fi; }
safe_delete_rule 1
[[ -f deleted ]]
''')
                self.assertEqual(result.returncode,0,result.stderr)
                (self.root/'deleted').unlink()
    def test_ufw_ssh_rule_failure_is_not_success(self):
        for name in ('ufw-rules-v4.sh','ufw-rules-v6.sh'):
            with self.subTest(name=name):
                result=self.bash(function(name,'create_ssh_rules')+'''
SSH_ALLOWED_IPS=(192.0.2.1)
SSH_PORT=22
safe_add_rule() { return 1; }
create_ssh_rules
''')
                self.assertNotEqual(result.returncode,0)
    def test_ufw_docker_sigterm_stops_execution(self):
        text=(SOURCE/'ufw-docker').read_text()
        traps='\n'.join(line for line in text.splitlines() if line.startswith('trap '))
        result=self.bash('on-exit() { :; }\n'+traps+'\nkill -TERM $$\nprintf continued\n')
        self.assertEqual(result.returncode,143)
        self.assertNotIn('continued',result.stdout)
    def test_swap_default_algorithm_flag_survives_prompt(self):
        for name in ('interactive_manual_input','interactive_edit_params'):
            text=(SOURCE/'swap-setup.sh').read_text()
            if name not in text:continue
            start=text.index('    ZRAM_ALGO=$(ask_value',text.index(name+'()')) if '    ZRAM_ALGO=$(ask_value' in text[text.index(name+'()'):] else text.index('    ask_value "   ALGO"',text.index(name+'()'))
            end=text.index('    validate_zram_algo',start)
            block=text[start:end]
            for answer,explicit in (('\n','false'),('lz4\n','true')):
                with self.subTest(prompt=name,answer=answer):
                    result=self.bash(function('swap-setup.sh','ask_value')+'\nZRAM_ALGO=zstd; ZRAM_ALGO_EXPLICIT=false; ASK_VALUE_USED_DEFAULT=false\n{\n'+block+'\n} >/dev/null\nprintf "%s|%s" "$ZRAM_ALGO" "$ZRAM_ALGO_EXPLICIT"',input=answer)
                    self.assertEqual(result.returncode,0,result.stderr)
                    self.assertEqual(result.stdout,('zstd' if answer=='\n' else 'lz4')+'|'+explicit)
    def test_swap_removal_stops_before_unlink_on_swapoff_failure(self):
        p=self.root/'swapfile';p.write_text('original')
        result=self.bash(function('swap-setup.sh','remove_swap').replace('/etc/',str(self.root/'etc')+'/')+'''
AUTO_YES=true
is_swapfile_active() { return 0; }
get_swap_priority() { printf 10; }
swapoff() { return 1; }
fstab_has_swapfile_entry() { return 1; }
stop_disable_zramswap_service() { :; }
SWAPFILE_PATH=$SWAP_TEST_FILE
remove_swap
''',env={'SWAP_TEST_FILE':str(p)})
        self.assertNotEqual(result.returncode,0)
        self.assertTrue(p.exists())
    def test_swap_replacement_failure_preserves_previous_active_file(self):
        for failure in ('format','activation','fstab'):
            with self.subTest(failure=failure):
                p=self.root/'swapfile';p.write_text('original')
                active=self.root/'active';active.write_text('yes')
                result=self.bash(function('swap-setup.sh','setup_swapfile')+'''
SWAPFILE_PATH=$SWAP_TEST_FILE; SWAPFILE_SIZE_MB=1; SWAP_PRIORITY=10; BTRFS_SWAP=false
register_temp_file() { :; }; check_disk_space() { :; }; check_filesystem_type() { :; }
is_swapfile_active() { [[ $(cat "$ACTIVE_FILE") == yes ]]; }
get_swap_priority() { printf 10; }
dd() { for arg in "$@"; do [[ $arg == of=* ]] && printf replacement > "${arg#of=}"; done; return 0; }
mkswap() { [[ $FAILURE != format ]]; }
swapoff() { printf no > "$ACTIVE_FILE"; }
swapon() {
    if [[ $FAILURE == activation && $(cat "$SWAPFILE_PATH") == replacement ]]; then return 1; fi
    printf yes > "$ACTIVE_FILE"
}
update_fstab() { [[ $FAILURE != fstab ]]; }
setup_swapfile
''',env={'SWAP_TEST_FILE':str(p),'ACTIVE_FILE':str(active),'FAILURE':failure})
                self.assertNotEqual(result.returncode,0)
                self.assertEqual(p.read_text(),'original',result.stderr)
                self.assertEqual(active.read_text(),'yes',result.stderr)
    def test_swap_fstab_preserves_other_entries_and_aborts_failed_stage(self):
        p=self.root/'fstab'
        original='# existing\n/dev/root / ext4 defaults 0 1\n/other none swap sw 0 0\n/swapfile none swap sw 0 0\n'
        code=function('swap-setup.sh','rewrite_fstab').replace('/etc/fstab',str(p))
        for fail in (True,False):
            p.write_text(original)
            result=self.bash(code+'''
SWAPFILE_PATH=/swapfile; SWAP_PRIORITY=10
register_temp_file() { :; }
chown() { [[ $FAIL_STAGE != yes ]]; }
rewrite_fstab true
''',env={'FAIL_STAGE':'yes' if fail else 'no'})
            if fail:
                self.assertNotEqual(result.returncode,0)
                self.assertEqual(p.read_text(),original)
            else:
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertEqual(p.read_text(),original.replace('/swapfile none swap sw 0 0','/swapfile none swap sw,pri=10 0 0'))
    def test_swap_zram_restart_failure_restores_previous_configuration(self):
        etc=self.root/'etc';(etc/'default').mkdir(parents=True)
        p=etc/'default/zramswap';p.write_text('ALGO=lz4\n')
        code=function('swap-setup.sh','setup_zram').replace('/etc/',str(etc)+'/')
        result=self.bash(code+'''
ZRAM_PERCENT=100; ZRAM_ALGO=zstd; ZRAM_PRIORITY=100; SWAP_PRIORITY=10
register_temp_file() { :; }
systemctl() { return 0; }
restart_zramswap_service() { return 1; }
setup_zram
''')
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(p.read_text(),'ALGO=lz4\n',result.stderr)
    def test_swap_swappiness_failure_restores_previous_configuration(self):
        etc=self.root/'etc';(etc/'sysctl.d').mkdir(parents=True)
        p=etc/'sysctl.d/99-swappiness.conf';p.write_text('vm.swappiness=30\n')
        code=function('swap-setup.sh','setup_swappiness').replace('/etc/',str(etc)+'/')
        result=self.bash(code+'''
SWAPPINESS=80
register_temp_file() { :; }; sysctl() { return 1; }
setup_swappiness
''')
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(p.read_text(),'vm.swappiness=30\n',result.stderr)
    def test_swap_invalid_cli_stops_before_install(self):
        for args in (['--unknown'],['--status','--remove'],['--status','--ram','1']):
            with self.subTest(args=args):
                result=subprocess.run(['bash',str(SOURCE/'swap-setup.sh'),*args],capture_output=True,text=True,timeout=5)
                self.assertNotEqual(result.returncode,0)
    def test_swap_numeric_validation_normalizes_decimal_and_rejects_invalid_priority(self):
        names=('validate_positive_int','validate_nonnegative_int','validate_zram_percent',
               'validate_zram_priority_value','validate_swappiness_value')
        code=''.join(function('swap-setup.sh',name) for name in names)
        result=self.bash(code+'''
SWAP_PRIORITY=10; ZRAM_PERCENT=008; ZRAM_PRIORITY=0100; SWAPPINESS=080
validate_zram_percent; validate_zram_priority_value; validate_swappiness_value
printf '%s|%s|%s' "$ZRAM_PERCENT" "$ZRAM_PRIORITY" "$SWAPPINESS"
''')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(result.stdout,'8|100|80')
        for value in ('0','10','32768','9999999999999999999','1+20'):
            result=self.bash(code+'\nSWAP_PRIORITY=10; ZRAM_PRIORITY=$BAD_PRIORITY; validate_zram_priority_value',env={'BAD_PRIORITY':value})
            self.assertNotEqual(result.returncode,0,value)
    def test_bbr_backup_failure_aborts_before_write(self):
        p=self.root/'sysctl.conf';p.write_text('original')
        code=function('bbr.sh','intelligent_settings').replace('/etc/sysctl.conf',str(p)).replace('/etc/modules-load.d',str(self.root))
        result=self.bash(code+'''
gather_system_info() { CPU_CORES=1; TOTAL_RAM=1024; }
cp() { return 1; }
modprobe() { :; }; ip() { :; }; sysctl() { :; }; prompt_reboot() { :; }
intelligent_settings
''')
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(p.read_text(),'original')
    def test_bbr_sysctl_failure_is_not_success(self):
        p=self.root/'sysctl.conf';p.write_text('original')
        code=function('bbr.sh','intelligent_settings').replace('/etc/sysctl.conf',str(p)).replace('/etc/modules-load.d',str(self.root))
        result=self.bash(code+'''
gather_system_info() { CPU_CORES=1; TOTAL_RAM=1024; }
modprobe() { :; }; ip() { :; }; sysctl() { return 1; }; prompt_reboot() { :; }
intelligent_settings
''')
        self.assertNotEqual(result.returncode,0)
        self.assertNotIn('net.ipv4.tcp_mem =',p.read_text())
    def test_bbr_handles_kernel_with_ipv6_disabled(self):
        p=self.root/'sysctl.conf';p.write_text('original')
        code=function('bbr.sh','intelligent_settings').replace('/etc/sysctl.conf',str(p)).replace('/etc/modules-load.d',str(self.root)).replace('/proc/sys/net/ipv6',str(self.root/'missing-ipv6'))
        result=self.bash(code+'''
gather_system_info() { CPU_CORES=1; TOTAL_RAM=1024; }
modprobe() { :; }; ip() { :; }; prompt_reboot() { :; }
sysctl() { ! grep -q '^net.ipv6' "$TEST_SYSCTL"; }
intelligent_settings
''',env={'TEST_SYSCTL':str(p)})
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertNotIn('net.ipv6.conf.',p.read_text())
    def test_bbr_package_failure_propagates(self):
        result=self.bash(function('bbr.sh','full_update_upgrade')+'\napt() { return 1; }; full_update_upgrade\n')
        self.assertNotEqual(result.returncode,0)
    def test_ufw_docker_missing_input_preserves_other_family(self):
        p=self.root/'after.rules';p.write_text('original')
        names=['ufw-docker--install','ufw-docker--check-install','ufw-docker--check-install_ipv6']
        result=self.bash(''.join(function('ufw-docker',n) for n in names)+'''
err() { :; }; rm-on-exit() { :; }
after_rules=$V4_FILE
after6_rules=$V6_FILE
ufw-docker--install
''',env={'V4_FILE':str(p),'V6_FILE':str(self.root/'missing')})
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(p.read_text(),'original')
    def motd_run(self,name,answer='y\n$(touch injected)\n',apt_failure=False,ssh_failure=False,payload=None):
        etc=self.root/'etc';etc.mkdir(exist_ok=True)
        updates=etc/'update-motd.d';updates.mkdir(exist_ok=True)
        (updates/'old').write_text('original')
        ssh=etc/'ssh';ssh.mkdir(exist_ok=True);(ssh/'sshd_config').write_text('Port 22\nMatch User fixture\n    X11Forwarding no\n')
        (etc/'motd').write_text('static-original')
        bin=self.root/'bin';bin.mkdir(exist_ok=True)
        stubs={'apt':f'exit {1 if apt_failure else 0}', 'apt-get':f'exit {1 if apt_failure else 0}',
               'curl':'while (($#)); do if [[ $1 == -o ]]; then cp "$FIXTURE_ARCHIVE" "$2"; exit; fi; shift; done; cat "$FIXTURE_ARCHIVE"',
               'sshd':f'exit {1 if ssh_failure else 0}', 'toilet':'printf "%s\\n" "$@"'}
        for command,body in stubs.items():
            p=bin/command;p.write_text('#!/bin/bash\n'+body+'\n');p.chmod(0o755)
        script=(SOURCE/name).read_text().replace('if [ "$EUID" -ne 0 ]; then','if false; then').replace('/usr/sbin/sshd',str(bin/'sshd')).replace('/etc/',str(etc)+'/').replace('/var/backups/system-setup',str(self.root/'backups'))
        run=self.root/'installer.sh';run.write_text(script)
        fixture=self.root/'motd-fixture.tar.gz'
        commit=re.search(r'(?m)^    MOTD_COMMIT=([a-f0-9]+)$',script)
        prefix='motd-ubuntu-debian-'+(commit[1] if commit else 'main')+'/motd/'
        members={'00-header':b'#!/bin/bash\n\nif command -v toilet >/dev/null; then toilet "you name"; else echo "you name"; fi\n',
                 'colors.txt':b'DEFAULT_COLOR=""\n', 'ivrit.flf':b'fixture\n',
                 '08-processes':b'#!/bin/bash\nPROCESS_COUNT=$(ps -ef | tail -n +2 | wc -l)\nprintf "%s" "$PROCESS_COUNT"\n',
                 '11-processes':b'#!/bin/bash\nexternal_ip=$(curl -s --max-time 2 ifconfig.me)\n'}
        if payload is not None:members['11-processes']=payload.encode()
        with tarfile.open(fixture,'w:gz') as archive:
            for leaf,data in members.items():
                item=tarfile.TarInfo(prefix+leaf);item.size=len(data);item.mode=0o644
                archive.addfile(item,io.BytesIO(data))
        digest=hashlib.sha256(fixture.read_bytes()).hexdigest()
        script=re.sub(r'(?m)^(    MOTD_ARCHIVE_SHA256=)[a-f0-9]+$',lambda m:m[1]+digest,script)
        run.write_text(script)
        env=dict(os.environ,PATH=str(bin)+':'+os.environ['PATH'],FIXTURE_ARCHIVE=str(fixture))
        result=subprocess.run(['bash',str(run)],cwd=self.root,input=answer,capture_output=True,text=True,timeout=15,env=env)
        return result,updates,env
    def test_motd_name_remains_literal_data(self):
        for name in ('motd-debian.sh','motd-ubuntu.sh'):
            with self.subTest(name=name):
                result,updates,env=self.motd_run(name)
                self.assertEqual(result.returncode,0,result.stderr)
                header=updates/'00-header'
                # The archive contains production paths; map only the synthetic
                # header's lookup to the test root before executing it.
                header.write_text(header.read_text().replace('source /etc/', 'source '+str(self.root/'etc')+'/').replace(' -d /etc/', ' -d '+str(self.root/'etc')+'/'))
                out=subprocess.run(['bash',str(header)],cwd=self.root,env=env,capture_output=True,text=True,timeout=5)
                self.assertEqual(out.returncode,0,out.stderr)
                self.assertFalse((self.root/'injected').exists())
                self.assertIn('$(touch injected)',out.stdout)
    def test_motd_apt_failure_keeps_configuration(self):
        result,updates,_=self.motd_run('motd-debian.sh',apt_failure=True)
        self.assertNotEqual(result.returncode,0)
        self.assertEqual((updates/'old').read_text(),'original')
    def test_motd_ssh_validation_failure_rolls_back(self):
        result,updates,_=self.motd_run('motd-ubuntu.sh',ssh_failure=True)
        self.assertNotEqual(result.returncode,0)
        self.assertEqual((updates/'old').read_text(),'original')
        self.assertEqual((self.root/'etc/motd').read_text(),'static-original')
    def test_motd_eof_does_not_install(self):
        result,updates,_=self.motd_run('motd-debian.sh',answer='')
        self.assertEqual(result.returncode,0)
        self.assertEqual((updates/'old').read_text(),'original')
    def test_motd_interfaces_drop_peer_suffix(self):
        payload='''#!/bin/bash
for iface in $(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -vE '^(lo|br-|veth)'); do
    ip -4 addr show "$iface"
done
'''
        for name in ('motd-debian.sh','motd-ubuntu.sh'):
            with self.subTest(name=name):
                result,updates,env=self.motd_run(name,payload=payload)
                self.assertEqual(result.returncode,0,result.stderr)
                p=self.root/'bin/ip';p.write_text('''#!/bin/bash
case "$*" in
    '-o link show') printf '2: eth0@if7: <UP> mtu 1500\\n' ;;
    '-4 addr show eth0') printf 'inet 192.0.2.10/24\\n' ;;
    *) exit 1 ;;
esac
''');p.chmod(0o755)
                result=subprocess.run(['bash',str(updates/'11-processes')],env=env,capture_output=True,text=True,timeout=5)
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertIn('192.0.2.10/24',result.stdout)
    def test_motd_certificate_scan_never_opens_private_paths(self):
        payload=r'''#!/bin/bash
for dir in "$CERT_FIXTURES"; do
    while IFS= read -r -d '' cert; do
        printf '%s\n' "$cert"
        done < <(find "$dir" -type f \( -name "*.crt" -o -name "*.pem" \) -print0 2>/dev/null)
done
'''
        certs=self.root/'certs';certs.mkdir()
        accepted=('leaf.crt','archive/example/cert1.pem','archive/example/chain2.pem','archive/example/fullchain2.pem')
        rejected=('privkey.pem','archive/example/privkey1.pem','server.pem','private/cert.pem',
                  'keys/cert.pem','accounts/cert.pem','server-key.crt','private/server.crt')
        # Placeholders contain no key material. The test records paths only.
        for leaf in (*accepted,*rejected):
            p=certs/leaf;p.parent.mkdir(parents=True,exist_ok=True);p.write_text('synthetic')
        (certs/'linked.crt').symlink_to(certs/'private/server.crt')
        for name in ('motd-debian.sh','motd-ubuntu.sh'):
            with self.subTest(name=name):
                result,updates,env=self.motd_run(name,payload=payload)
                self.assertEqual(result.returncode,0,result.stderr)
                env['CERT_FIXTURES']=str(certs)
                result=subprocess.run(['bash',str(updates/'11-processes')],env=env,capture_output=True,text=True,timeout=5)
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertEqual(set(result.stdout.splitlines()),{str(certs/leaf) for leaf in accepted})
    def test_motd_process_count_does_not_request_command_arguments(self):
        result,updates,env=self.motd_run('motd-debian.sh')
        self.assertEqual(result.returncode,0,result.stderr)
        p=self.root/'bin/ps';p.write_text('''#!/bin/bash
[[ "$*" == '-e -o pid=' ]] || exit 1
printf '1\\n2\\n3\\n'
''');p.chmod(0o755)
        result=subprocess.run(['bash',str(updates/'08-processes')],env=env,capture_output=True,text=True,timeout=5)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(result.stdout.strip(),'3')

if __name__=='__main__':unittest.main()
