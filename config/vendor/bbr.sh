#!/bin/bash
# Source: https://raw.githubusercontent.com/civisrom/Linux_NetworkOptimizer/d97fd79bac63dfd98f0d0f4f6d626395b16e31c9/bbr.sh
# Local safety fixes; see README.md in this directory.

#############################################
# Network Optimizer Script with BBR
# Version: 0.8 Enhanced
# Author: DevElf (Enhanced by civisrom)
# Description: Advanced network optimization with optional components
#############################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Script version
SCRIPT_VERSION="0.8"

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root.${NC}"
    exit 1
fi

# Function to display the logo and system information
function show_header() {
    echo -e "\n${BLUE}==========================================${NC}"
    echo -e "${CYAN}   Network Optimizer Script V${SCRIPT_VERSION}${NC}"
    echo -e "${BLUE}==========================================${NC}"

    echo -e "${GREEN}Hostname       : $(hostname)${NC}"

    # Get OS description using lsb_release; fallback to /etc/os-release if needed
    os_info=$(lsb_release -d 2>/dev/null | cut -f2)
    if [ -z "$os_info" ]; then
        os_info=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d '=' -f2 | tr -d '"')
    fi
    echo -e "${GREEN}OS             : $os_info${NC}"

    echo -e "${GREEN}Kernel Version : $(uname -r)${NC}"
    echo -e "${GREEN}Uptime         : $(uptime -p)${NC}"
    echo -e "${GREEN}IP Address     : $(hostname -I | awk '{print $1}')${NC}"

    # Get CPU model information
    cpu_model=$(grep -m1 'model name' /proc/cpuinfo | cut -d ':' -f2 | xargs)
    echo -e "${GREEN}CPU            : $cpu_model${NC}"

    echo -e "${GREEN}Architecture   : $(uname -m)${NC}"

    # Display memory usage in a human-readable format
    mem_usage=$(free -h | awk '/^Mem:/{print $3 " / " $2}')
    echo -e "${GREEN}Memory Usage   : $mem_usage${NC}"

    # Extract load average from uptime output and trim leading space
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | sed 's/^ //')
    echo -e "${GREEN}Load Average   : $load_avg${NC}"

    echo -e "${BLUE}==========================================${NC}\n"
}

# Function to print colored messages
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Fix /etc/hosts file
function fix_etc_hosts() {
    local host_path=${1:-/etc/hosts}

    print_warning "Starting to fix the hosts file..."

    # Backup current hosts file
    local timestamp=$(date +%Y%m%d-%H%M%S)
    if cp "$host_path" "${host_path}~${timestamp}"; then
        print_message "Hosts file backed up as ${host_path}~${timestamp}"
    else
        print_error "Backup failed. Cannot proceed."
        return 1
    fi

    # Check if hostname is in hosts file; add if missing
    if ! grep -q "$(hostname)" "$host_path"; then
        if echo "127.0.1.1 $(hostname)" | tee -a "$host_path" > /dev/null; then
            print_success "Hostname entry added to hosts file."
        else
            print_error "Failed to add hostname entry."
            return 1
        fi
    else
        print_success "Hostname entry already present. No changes needed."
    fi
}

# Temporarily fix DNS by modifying /etc/resolv.conf
function fix_dns() {
    local dns_path=${1:-/etc/resolv.conf}

    print_warning "Starting to update DNS configuration..."

    # Backup current DNS settings
    local timestamp=$(date +%Y%m%d-%H%M%S)
    if cp "$dns_path" "${dns_path}~${timestamp}"; then
        print_message "DNS configuration backed up as ${dns_path}~${timestamp}"
    else
        print_error "Backup failed. Cannot proceed."
        return 1
    fi

    # Clear current nameservers and add Cloudflare DNS
    if sed -i '/nameserver/d' "$dns_path" && {
        echo "nameserver 1.1.1.1" | tee -a "$dns_path" > /dev/null
        echo "nameserver 1.0.0.1" | tee -a "$dns_path" > /dev/null
        echo "nameserver 8.8.8.8" | tee -a "$dns_path" > /dev/null
        echo "nameserver 8.8.4.4" | tee -a "$dns_path" > /dev/null
    }; then
        print_success "Cloudflare DNS servers set successfully (1.1.1.1, 8.8.8.8)."
    else
        print_error "Failed to update DNS configuration."
        return 1
    fi
}

# Force IPv4 for APT
force_ipv4_apt() {
    local config_file="/etc/apt/apt.conf.d/99force-ipv4"
    local config_line='Acquire::ForceIPv4 "true";'

    # Check if the configuration already exists
    if [[ -f "$config_file" && "$(grep -Fx "$config_line" "$config_file")" == "$config_line" ]]; then
        print_success "IPv4 force for APT is already configured in $config_file."
        return 0
    fi

    # Add the configuration
    echo "$config_line" | tee "$config_file" >/dev/null
    if [[ $? -eq 0 ]]; then
        print_success "IPv4 force for APT configured successfully in $config_file."
    else
        print_error "Failed to configure IPv4 force for APT."
        return 1
    fi
}

# Function to fully update and upgrade the server
function full_update_upgrade() {
    print_warning "Updating package list..."
    apt -o Acquire::ForceIPv4=true update || return 1

    print_warning "Upgrading installed packages..."
    apt -o Acquire::ForceIPv4=true upgrade -y || return 1

    print_warning "Performing full distribution upgrade..."
    apt -o Acquire::ForceIPv4=true dist-upgrade -y || return 1

    print_warning "Removing unnecessary packages..."
    apt -o Acquire::ForceIPv4=true autoremove -y || return 1

    print_warning "Cleaning up any cached packages..."
    apt -o Acquire::ForceIPv4=true autoclean || return 1

    print_success "Server update and upgrade complete."
}

# Function to gather system information
function gather_system_info() {
    CPU_CORES=$(nproc)
    TOTAL_RAM=$(free -m | awk '/Mem:/ { print $2 }')
    print_success "Detected CPU cores: $CPU_CORES"
    print_success "Detected Total RAM: ${TOTAL_RAM}MB"
}

# Function to intelligently set buffer sizes and sysctl settings
function intelligent_settings() {
    echo ""
    print_warning "Starting intelligent network optimizations..."
    echo ""

    print_message "Gathering system information..."
    gather_system_info
    sleep 1

    echo ""
    print_message "Starting sysctl configuration..."
    sleep 1

    print_warning "Backing up current sysctl.conf..."
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="/etc/sysctl.conf~${timestamp}"
    if ls /etc/sysctl.conf~* 1> /dev/null 2>&1; then
        print_warning "Backup already exists. Creating new backup anyway..."
    fi
    if [[ -e /etc/sysctl.conf ]] && ! cp -p /etc/sysctl.conf "$backup_file"; then
        print_error "Cannot back up sysctl.conf; configuration was not changed"
        return 1
    fi
    print_success "Backup created: $backup_file"

    ############################################################################
    # Dynamic tuning based on hardware resources with values adjusted for
    # serving clients with low internet speed and lossy networks.
    #
    # These values have been set more conservatively while still optimizing for
    # high TCP connection counts and efficiency.
    ############################################################################
    print_message "Calculating optimal network parameters based on hardware..."

    if [ "$TOTAL_RAM" -lt 2000 ] && [ "$CPU_CORES" -le 2 ]; then
        # Low-end system
        rmem_max=2097152         # 2 MB
        wmem_max=2097152         # 2 MB
        netdev_max_backlog=100000
        queuing_disc="fq_codel"
        print_message "Profile: Low-end system (< 2GB RAM, <= 2 cores)"
    elif [ "$TOTAL_RAM" -lt 4000 ] && [ "$CPU_CORES" -le 4 ]; then
        # Mid-range system
        rmem_max=4194304         # 4 MB
        wmem_max=4194304         # 4 MB
        netdev_max_backlog=200000
        queuing_disc="fq_codel"
        print_message "Profile: Mid-range system (2-4GB RAM, 2-4 cores)"
    else
        # High-end system
        rmem_max=8388608         # 8 MB
        wmem_max=8388608         # 8 MB
        netdev_max_backlog=300000
        queuing_disc="cake"
        print_message "Profile: High-end system (> 4GB RAM, > 4 cores)"
    fi

    tcp_rmem="4096 87380 $rmem_max"
    tcp_wmem="4096 65536 $wmem_max"
    tcp_congestion_control="bbr"
    tcp_retries2=12

    print_success "Network parameters calculated successfully"
    print_message "  - rmem_max: $rmem_max bytes"
    print_message "  - wmem_max: $wmem_max bytes"
    print_message "  - netdev_max_backlog: $netdev_max_backlog"
    print_message "  - Queuing discipline: $queuing_disc"
    print_message "  - TCP congestion control: $tcp_congestion_control"
    print_message "  - TCP retries: $tcp_retries2"

    ############################################################################
    # Overwrite /etc/sysctl.conf with the new configuration including
    # additional parameters for high TCP connection handling and efficiency.
    ############################################################################
    print_message "Writing optimized configuration to /etc/sysctl.conf..."

    # A live interface ignores conf.default; send/secure redirects use the OR of
    # conf.all and the interface, so the WAN interface is also set by name.
    local wan_if wan_settings=""
    wan_if=$(ip -4 route show default 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit }}')
    if [[ "$wan_if" =~ ^[A-Za-z0-9_-]{1,15}$ ]]; then
        wan_settings="net.ipv4.conf.${wan_if}.send_redirects = 0
net.ipv4.conf.${wan_if}.accept_redirects = 0
net.ipv4.conf.${wan_if}.secure_redirects = 0"
    fi

    local ipv6_settings="" scope
    for scope in all default lo; do
        if [[ -e /proc/sys/net/ipv6/conf/$scope/disable_ipv6 ]]; then
            ipv6_settings+="net.ipv6.conf.${scope}.disable_ipv6 = 1"$'\n'
        fi
    done

    if ! cat <<EOL > /etc/sysctl.conf

## File system settings
fs.file-max = 67108864

## Network core settings
net.core.default_qdisc = $queuing_disc
net.core.netdev_max_backlog = $netdev_max_backlog
net.core.optmem_max = 65536
net.core.somaxconn = 65536
net.core.rmem_max = $rmem_max
net.core.rmem_default = 524288    # 512 KB tuned for low-speed links
net.core.wmem_max = $wmem_max
net.core.wmem_default = 524288    # 512 KB tuned for low-speed links

## TCP settings
net.ipv4.tcp_rmem = $tcp_rmem
net.ipv4.tcp_wmem = $tcp_wmem
net.ipv4.tcp_congestion_control = $tcp_congestion_control
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_probes = 7
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_max_orphans = 1048576
net.ipv4.tcp_max_syn_backlog = 262144
net.ipv4.tcp_max_tw_buckets = 1440000
# tcp_mem uses memory pages; retain the kernel defaults derived from RAM.
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_retries2 = $tcp_retries2
net.ipv4.tcp_sack = 1
net.ipv4.tcp_dsack = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_ecn = 1
net.ipv4.tcp_ecn_fallback = 1
net.ipv4.tcp_syncookies = 1

# Additional TCP tuning for high connection loads and efficiency:
net.ipv4.tcp_tw_reuse = 1                   # Reuse TIME_WAIT sockets for new connections
net.ipv4.tcp_fastopen = 3                   # Enable TCP Fast Open on both client and server sides
net.ipv4.ip_local_port_range = 1024 65535   # Expand ephemeral port range
net.ipv4.tcp_rfc1337 = 1                    # Improve behavior for port exhaustion

## UDP settings
net.ipv4.udp_mem = 65536 131072 262144

## IPv6 settings (disabled for optimization)
${ipv6_settings}

## UNIX domain sockets
net.unix.max_dgram_qlen = 256

## Virtual memory (VM) settings
vm.min_free_kbytes = 131072
vm.swappiness = 10
vm.vfs_cache_pressure = 250

## Network configuration
net.ipv4.conf.default.rp_filter = 2
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.neigh.default.gc_thresh1 = 512
net.ipv4.neigh.default.gc_thresh2 = 2048
net.ipv4.neigh.default.gc_thresh3 = 16384
net.ipv4.neigh.default.gc_stale_time = 60
net.ipv4.conf.default.arp_announce = 2
net.ipv4.conf.lo.arp_announce = 2
net.ipv4.conf.all.arp_announce = 2

## Protection from hosting-segment neighbours: answer ARP only for addresses of
## the receiving interface; never send or accept ICMP redirects.
net.ipv4.conf.all.arp_ignore = 1
net.ipv4.conf.default.arp_ignore = 1
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
${wan_settings}
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

net.netfilter.nf_conntrack_max = 131072
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_established = 86400
net.netfilter.nf_conntrack_tcp_loose = 0

## Kernel settings
kernel.panic = 1
vm.dirty_ratio = 10
EOL
    then
        print_error "Cannot write sysctl.conf"
        return 1
    fi

    print_success "Network optimizations written to /etc/sysctl.conf"

    # net.netfilter.* exist only after nf_conntrack is loaded. systemd-sysctl
    # runs early at boot and silently skips them unless modules-load loads it.
    printf 'nf_conntrack\n' > /etc/modules-load.d/network-optimizer-conntrack.conf
    modprobe nf_conntrack 2>/dev/null || print_warning "nf_conntrack is not loadable now; conntrack settings apply after it loads"

    print_message "Applying sysctl settings..."
    if sysctl -p > /dev/null 2>&1; then
        print_success "Network settings applied successfully!"
    else
        print_error "Failed to apply some sysctl settings"
        print_warning "Check /var/log/syslog for details"
        return 1
    fi

    # Log the final dynamic values for reference
    echo ""
    print_message "Configuration summary:"
    echo "  Total RAM: $TOTAL_RAM MB"
    echo "  CPU Cores: $CPU_CORES"
    echo "  rmem_max: $rmem_max bytes"
    echo "  wmem_max: $wmem_max bytes"
    echo "  netdev_max_backlog: $netdev_max_backlog"
    echo "  tcp_rmem: $tcp_rmem"
    echo "  tcp_wmem: $tcp_wmem"
    echo "  TCP Congestion Control: $tcp_congestion_control"
    echo "  tcp_retries2: $tcp_retries2"
    echo "  Queuing discipline: $queuing_disc"
    echo ""

    prompt_reboot
}

# Function to restore the original sysctl settings
function restore_original() {
    # Find the most recent backup
    LATEST_BACKUP=$(ls -t /etc/sysctl.conf~* 2>/dev/null | head -1)

    if [ ! -z "$LATEST_BACKUP" ]; then
        print_warning "Restoring original network settings from backup: $LATEST_BACKUP"
        cp "$LATEST_BACKUP" /etc/sysctl.conf

        if sysctl -p > /dev/null 2>&1; then
            print_success "Network settings restored successfully!"
        else
            print_error "Failed to apply restored settings"
        fi

        prompt_reboot
    else
        print_error "No backup found. Cannot restore original settings."
        print_warning "Available backups should have format: /etc/sysctl.conf~YYYYMMDD-HHMMSS"

        # Prompt user to press any key to continue
        read -n 1 -s -r -p "Press any key to continue..."
        echo # for a new line
    fi
}

# Function to find best MTU
find_best_mtu() {
    local server_ip=${1:-8.8.8.8}   # Default: Google DNS server
    local low=1200          # Lower bound MTU
    local high=1500         # Standard MTU
    local optimal=0

    print_message "Starting MTU search for server: $server_ip"

    # Check if the server is reachable
    if ! ping -c 1 -W 1 "$server_ip" &>/dev/null; then
        print_error "Server $server_ip unreachable."
        return 1
    fi

    # Verify that the minimum MTU works
    if ! ping -M do -s $((low - 28)) -c 1 "$server_ip" &>/dev/null; then
        print_error "Minimum MTU of $low bytes not viable."
        return 1
    fi

    optimal=$low
    print_message "Searching for optimal MTU using binary search..."

    # Use binary search to find the highest MTU that works
    while [ $low -le $high ]; do
        local mid=$(( (low + high) / 2 ))
        if ping -M do -s $((mid - 28)) -c 1 "$server_ip" &>/dev/null; then
            optimal=$mid
            low=$(( mid + 1 ))
        else
            high=$(( mid - 1 ))
        fi
    done

    print_success "Optimal MTU found: ${optimal} bytes"

    # Ask user if they want to set the current MTU to the found value
    echo ""
    read -p "Do you want to set the optimal MTU on a network interface? (Y/n): " set_mtu_choice
    set_mtu_choice=${set_mtu_choice:-y}

    if [[ "$set_mtu_choice" =~ ^[Yy] ]]; then
        # List available network interfaces
        print_message "Available network interfaces:"
        ip -brief link show | awk '{print "  - " $1}'
        echo ""

        read -p "Enter the network interface name: " iface
        if [[ -z "$iface" ]]; then
            print_error "No interface provided."
            return 1
        fi

        # Verify interface exists
        if ! ip link show "$iface" &>/dev/null; then
            print_error "Interface $iface does not exist."
            return 1
        fi

        # Attempt to set the MTU using the ip command
        if ip link set dev "$iface" mtu "$optimal"; then
            print_success "MTU set to ${optimal} bytes on interface $iface"

            # Ask if user wants to make it permanent
            echo ""
            read -p "Do you want to make this MTU setting permanent? (y/N): " make_permanent
            make_permanent=${make_permanent:-n}

            if [[ "$make_permanent" =~ ^[Yy] ]]; then
                # Try to make it permanent (method depends on network manager)
                if command -v nmcli &>/dev/null; then
                    # NetworkManager is available
                    CONNECTION=$(nmcli -t -f NAME,DEVICE connection show --active | grep "$iface" | cut -d: -f1)
                    if [ ! -z "$CONNECTION" ]; then
                        nmcli connection modify "$CONNECTION" 802-3-ethernet.mtu "$optimal"
                        print_success "MTU set permanently via NetworkManager for connection: $CONNECTION"
                    else
                        print_warning "Could not find NetworkManager connection for $iface"
                    fi
                else
                    # Fall back to /etc/network/interfaces (Debian/Ubuntu)
                    print_warning "Permanent MTU configuration requires manual editing of:"
                    print_message "  - /etc/network/interfaces (Debian/Ubuntu)"
                    print_message "  - /etc/sysconfig/network-scripts/ifcfg-$iface (RHEL/CentOS)"
                    print_message "Add: mtu $optimal"
                fi
            fi
        else
            print_error "Failed to set MTU on interface $iface"
            return 1
        fi
    else
        print_message "MTU setting skipped by user."
    fi

    return 0
}

# Function to prompt the user for a reboot
function prompt_reboot() {
    echo ""
    read -p "It is recommended to reboot for changes to take effect. Reboot now? (y/[N]): " reboot_choice
    reboot_choice=${reboot_choice:-n}

    if [[ "$reboot_choice" =~ ^[Yy] ]]; then
        print_warning "Rebooting now..."
        sleep 2
        reboot
    else
        print_warning "Reboot skipped. Please remember to reboot manually for all changes to take effect."
    fi

    # Prompt user to press any key to continue
    echo ""
    read -n 1 -s -r -p "Press any key to continue..."
    echo # for a new line
}

# Function to run optional pre-optimization tasks
function run_optional_tasks() {
    echo ""
    print_warning "Optional System Preparation Tasks"
    echo ""
    print_message "These tasks can help prepare your system before applying optimizations:"
    print_message "1. Fix /etc/hosts file (add hostname entry)"
    print_message "2. Fix DNS configuration (set Cloudflare DNS)"
    print_message "3. Force IPv4 for APT (helps with IPv6 connectivity issues)"
    print_message "4. Full system update and upgrade"
    echo ""

    # Fix /etc/hosts
    read -p "Run fix_etc_hosts? (y/N): " run_hosts
    run_hosts=${run_hosts:-n}
    if [[ "$run_hosts" =~ ^[Yy] ]]; then
        echo ""
        fix_etc_hosts
        sleep 2
    fi

    # Fix DNS
    read -p "Run fix_dns? (y/N): " run_dns
    run_dns=${run_dns:-n}
    if [[ "$run_dns" =~ ^[Yy] ]]; then
        echo ""
        fix_dns
        sleep 2
    fi

    # Force IPv4 for APT
    read -p "Run force_ipv4_apt? (y/N): " run_ipv4
    run_ipv4=${run_ipv4:-n}
    if [[ "$run_ipv4" =~ ^[Yy] ]]; then
        echo ""
        force_ipv4_apt
        sleep 2
    fi

    # Full update
    read -p "Run full_update_upgrade? (y/N): " run_update
    run_update=${run_update:-n}
    if [[ "$run_update" =~ ^[Yy] ]]; then
        echo ""
        full_update_upgrade
        sleep 2
    fi

    echo ""
    print_success "Optional tasks completed"
    echo ""
}

# Function to display the menu
function show_menu() {
    while true; do
        clear
        show_header
        echo -e "${CYAN}=== Main Menu ===${NC}"
        echo -e "${GREEN}1. Apply BBR and Intelligent Optimizations${NC}"
        echo -e "${GREEN}2. Run Optional Preparation Tasks${NC}"
        echo -e "${GREEN}3. Find Best MTU for Server${NC}"
        echo -e "${GREEN}4. Restore Original Settings${NC}"
        echo -e "${GREEN}5. View Current Network Settings${NC}"
        echo -e "${GREEN}0. Exit${NC}"
        echo ""
        read -p "Enter your choice: " choice

        case $choice in
            1)
                clear
                show_header
                intelligent_settings
                ;;
            2)
                clear
                show_header
                run_optional_tasks
                ;;
            3)
                clear
                show_header
                echo ""
                print_message "MTU Discovery Tool"
                echo ""
                read -p "Enter target server IP (default: 8.8.8.8): " target_ip
                target_ip=${target_ip:-8.8.8.8}
                find_best_mtu "$target_ip"
                echo ""
                read -n 1 -s -r -p "Press any key to continue..."
                ;;
            4)
                clear
                show_header
                restore_original
                ;;
            5)
                clear
                show_header
                echo ""
                print_message "Current Network Settings:"
                echo ""
                echo -e "${CYAN}TCP Congestion Control:${NC}"
                sysctl net.ipv4.tcp_congestion_control
                echo ""
                echo -e "${CYAN}TCP Memory Settings:${NC}"
                sysctl net.ipv4.tcp_mem
                echo ""
                echo -e "${CYAN}TCP Window Sizes:${NC}"
                sysctl net.ipv4.tcp_rmem
                sysctl net.ipv4.tcp_wmem
                echo ""
                echo -e "${CYAN}Queue Discipline:${NC}"
                sysctl net.core.default_qdisc
                echo ""
                echo -e "${CYAN}Network Backlog:${NC}"
                sysctl net.core.netdev_max_backlog
                echo ""
                echo -e "${CYAN}IPv6 Status:${NC}"
                sysctl net.ipv6.conf.all.disable_ipv6
                echo ""
                read -n 1 -s -r -p "Press any key to continue..."
                ;;
            0)
                echo ""
                print_warning "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid option. Please try again."
                sleep 2
                ;;
        esac
    done
}

# Check if script is being sourced (for integration with other scripts)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly, show menu
    show_menu
else
    # Script is being sourced, functions are available but menu is not shown
    print_success "BBR Network Optimizer functions loaded successfully"
fi
