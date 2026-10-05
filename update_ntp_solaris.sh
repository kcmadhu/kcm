#!/bin/bash

###############################################################################
# Script: update_ntp_solaris.sh
# Purpose: Update ntp.conf on Solaris servers with connectivity validation
# Author: System Administrator
# Description: Detects running NTP service, validates connectivity to NTP servers
#              (CMN and EDN IPs), and updates ntp.conf with missing entries
###############################################################################

set -o pipefail

# Configuration
LOGFILE="/var/log/ntp_update_$(date +%Y%m%d_%H%M%S).log"
NTP_CONF="/etc/inet/ntp.conf"
NTP_CONF_BACKUP="${NTP_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
CONNECTIVITY_TEST_TIMEOUT=5

# NTP Server IPs - CMN and EDN
CMN_IPS=("10.x.x.x" "10.x.x.x" "10.x.x.x" "10.x.x.x")
EDN_IPS=("10.y.y.y" "10.y.y.y" "10.y.y.y" "10.y.y.y")
NTP_PORT=123

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

###############################################################################
# Logging Function
###############################################################################
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "$LOGFILE"
}

###############################################################################
# Print formatted output with color
###############################################################################
print_status() {
    local status=$1
    local message=$2
    case "$status" in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} ${message}"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} ${message}"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} ${message}"
            ;;
    esac
}

###############################################################################
# Step 1: Detect running NTP service
###############################################################################
detect_ntp_service() {
    log "INFO" "Step 1: Detecting running NTP service..."
    print_status "INFO" "Checking for active NTP service..."

    # Check for various NTP services
    if pgrep -x "xntpd" > /dev/null; then
        NTP_SERVICE="xntpd"
        log "INFO" "Detected service: xntpd"
        return 0
    elif pgrep -x "ntpd" > /dev/null; then
        NTP_SERVICE="ntpd"
        log "INFO" "Detected service: ntpd"
        return 0
    elif pgrep -x "chronyd" > /dev/null; then
        NTP_SERVICE="chronyd"
        log "INFO" "Detected service: chronyd"
        return 0
    elif svcs -H ntp/server 2>/dev/null | grep -q "online"; then
        NTP_SERVICE="SMF_NTP"
        log "INFO" "Detected service: SMF NTP (Solaris Service Management)"
        return 0
    else
        log "ERROR" "No running NTP service detected"
        print_status "ERROR" "No active NTP service found. Exiting."
        return 1
    fi
}

###############################################################################
# Step 2: Verify service is running
###############################################################################
verify_service_running() {
    log "INFO" "Step 2: Verifying NTP service is running..."
    
    case "$NTP_SERVICE" in
        "xntpd")
            if pgrep -x "xntpd" > /dev/null; then
                print_status "INFO" "Service $NTP_SERVICE is running"
                return 0
            fi
            ;;
        "ntpd")
            if pgrep -x "ntpd" > /dev/null; then
                print_status "INFO" "Service $NTP_SERVICE is running"
                return 0
            fi
            ;;
        "chronyd")
            if pgrep -x "chronyd" > /dev/null; then
                print_status "INFO" "Service $NTP_SERVICE is running"
                return 0
            fi
            ;;
        "SMF_NTP")
            if svcs -H ntp/server 2>/dev/null | grep -q "online"; then
                print_status "INFO" "Service $NTP_SERVICE is running"
                return 0
            fi
            ;;
    esac
    
    log "ERROR" "Service $NTP_SERVICE is not running"
    print_status "ERROR" "NTP service is not running. Exiting."
    return 1
}

###############################################################################
# Step 3: Find ntp.conf configuration file
###############################################################################
find_ntp_config() {
    log "INFO" "Step 3: Locating ntp.conf configuration file..."
    
    if [ -f "$NTP_CONF" ]; then
        print_status "INFO" "Found ntp.conf at: $NTP_CONF"
        log "INFO" "Configuration file found at $NTP_CONF"
        return 0
    else
        log "ERROR" "ntp.conf not found at $NTP_CONF"
        print_status "ERROR" "Configuration file not found. Exiting."
        return 1
    fi
}

###############################################################################
# Step 4: Test connectivity using ntpdate or nc
###############################################################################
test_connectivity() {
    local ip_array=$1
    local array_name=$2
    
    log "INFO" "Testing connectivity to $array_name IPs..."
    print_status "INFO" "Testing connectivity to $array_name servers..."
    
    local pass_count=0
    local total_count=${#ip_array[@]}
    local reachable_ips=()
    
    for ip in "${ip_array[@]}"; do
        # Try ntpdate first
        if command -v ntpdate &> /dev/null; then
            if timeout $CONNECTIVITY_TEST_TIMEOUT ntpdate -q "$ip" &>/dev/null; then
                log "INFO" "Connectivity test PASSED for $ip using ntpdate"
                reachable_ips+=("$ip")
                ((pass_count++))
                continue
            fi
        fi
        
        # Fallback to nc (netcat)
        if command -v nc &> /dev/null; then
            if timeout $CONNECTIVITY_TEST_TIMEOUT nc -zv "$ip" $NTP_PORT &>/dev/null; then
                log "INFO" "Connectivity test PASSED for $ip using nc"
                reachable_ips+=("$ip")
                ((pass_count++))
                continue
            fi
        fi
        
        log "WARN" "Connectivity test FAILED for $ip"
    done
    
    log "INFO" "Connectivity results for $array_name: $pass_count/$total_count passed"
    echo "${reachable_ips[@]}"
}

###############################################################################
# Step 5: Test CMN connectivity (4/4 requirement)
###############################################################################
test_cmn_connectivity() {
    log "INFO" "Step 4: Testing CMN connectivity (4/4)..."
    print_status "INFO" "Testing CMN servers (requires 4/4 to pass)..."
    
    local cmn_ips=($(test_connectivity "${CMN_IPS[@]}" "CMN"))
    
    if [ ${#cmn_ips[@]} -eq 4 ]; then
        log "INFO" "CMN connectivity test PASSED (4/4)"
        print_status "INFO" "CMN connectivity: PASS"
        SELECTED_IPS=("${cmn_ips[@]}")
        return 0
    else
        log "WARN" "CMN connectivity test FAILED (${#cmn_ips[@]}/4)"
        print_status "WARN" "CMN connectivity failed. Testing EDN servers..."
        return 1
    fi
}

###############################################################################
# Step 6: Test EDN connectivity (4/4 requirement)
###############################################################################
test_edn_connectivity() {
    log "INFO" "Step 5: Testing EDN connectivity (4/4)..."
    print_status "INFO" "Testing EDN servers (requires 4/4 to pass)..."
    
    local edn_ips=($(test_connectivity "${EDN_IPS[@]}" "EDN"))
    
    if [ ${#edn_ips[@]} -eq 4 ]; then
        log "INFO" "EDN connectivity test PASSED (4/4)"
        print_status "INFO" "EDN connectivity: PASS"
        SELECTED_IPS=("${edn_ips[@]}")
        return 0
    else
        log "ERROR" "EDN connectivity test FAILED (${#edn_ips[@]}/4)"
        print_status "ERROR" "Both CMN and EDN connectivity tests failed. Exiting."
        return 1
    fi
}

###############################################################################
# Step 7: Check if selected IPs already exist in ntp.conf
###############################################################################
check_existing_ips() {
    log "INFO" "Step 6: Checking for existing server entries in ntp.conf..."
    print_status "INFO" "Verifying existing NTP server entries..."
    
    local missing_ips=()
    
    for ip in "${SELECTED_IPS[@]}"; do
        if grep -q "^server $ip" "$NTP_CONF"; then
            log "INFO" "Server entry already exists for $ip"
        else
            log "INFO" "Server entry missing for $ip"
            missing_ips+=("$ip")
        fi
    done
    
    if [ ${#missing_ips[@]} -eq 0 ]; then
        log "INFO" "All selected IPs already exist in ntp.conf"
        print_status "INFO" "All NTP server entries are already configured. Exiting."
        return 1
    else
        log "INFO" "Found ${#missing_ips[@]} missing IP entries"
        MISSING_IPS=("${missing_ips[@]}")
        return 0
    fi
}

###############################################################################
# Step 8: Backup existing configuration
###############################################################################
backup_config() {
    log "INFO" "Step 7: Creating backup of existing ntp.conf..."
    
    if cp "$NTP_CONF" "$NTP_CONF_BACKUP"; then
        log "INFO" "Backup created successfully: $NTP_CONF_BACKUP"
        print_status "INFO" "Backup created: $NTP_CONF_BACKUP"
        return 0
    else
        log "ERROR" "Failed to create backup of ntp.conf"
        print_status "ERROR" "Failed to backup configuration. Exiting."
        return 1
    fi
}

###############################################################################
# Step 9: Insert missing IPs after last server line
###############################################################################
insert_missing_ips() {
    log "INFO" "Step 8: Inserting missing server entries into ntp.conf..."
    print_status "INFO" "Adding missing NTP server entries..."
    
    # Find the last server line number
    local last_server_line=$(grep -n "^server " "$NTP_CONF" | tail -1 | cut -d: -f1)
    
    if [ -z "$last_server_line" ]; then
        # No existing server entries, add after any comments/config
        last_server_line=$(wc -l < "$NTP_CONF")
    fi
    
    log "INFO" "Last server entry found at line: $last_server_line"
    
    # Create temporary file with insertions
    local temp_file="${NTP_CONF}.tmp"
    cp "$NTP_CONF" "$temp_file"
    
    # Insert missing IPs
    local insert_count=0
    for ip in "${MISSING_IPS[@]}"; do
        sed -i "${last_server_line}a\\server $ip iburst" "$temp_file"
        log "INFO" "Added server entry for $ip"
        ((last_server_line++))
        ((insert_count++))
    done
    
    # Replace original with modified file
    if mv "$temp_file" "$NTP_CONF"; then
        log "INFO" "Successfully inserted $insert_count new server entries"
        print_status "INFO" "Added $insert_count new NTP server entries"
        return 0
    else
        log "ERROR" "Failed to update ntp.conf"
        print_status "ERROR" "Failed to update configuration file. Exiting."
        return 1
    fi
}

###############################################################################
# Step 10: Verify changes
###############################################################################
verify_changes() {
    log "INFO" "Step 9: Verifying changes to ntp.conf..."
    print_status "INFO" "Verifying configuration changes..."
    
    local verification_failed=0
    
    for ip in "${MISSING_IPS[@]}"; do
        if grep -q "^server $ip" "$NTP_CONF"; then
            log "INFO" "Verification PASSED for $ip"
        else
            log "ERROR" "Verification FAILED for $ip"
            verification_failed=1
        fi
    done
    
    if [ $verification_failed -eq 0 ]; then
        log "INFO" "All changes verified successfully"
        print_status "INFO" "Verification: SUCCESS"
        return 0
    else
        log "ERROR" "Verification failed for one or more entries"
        print_status "ERROR" "Verification failed. Restoring from backup..."
        restore_from_backup
        return 1
    fi
}

###############################################################################
# Restore from backup on failure
###############################################################################
restore_from_backup() {
    log "WARN" "Restoring ntp.conf from backup..."
    
    if cp "$NTP_CONF_BACKUP" "$NTP_CONF"; then
        log "INFO" "Restored ntp.conf from backup"
        print_status "INFO" "Configuration restored from backup"
    else
        log "ERROR" "Failed to restore from backup"
        print_status "ERROR" "Failed to restore backup"
        return 1
    fi
}

###############################################################################
# Step 11: Restart NTP service
###############################################################################
restart_ntp_service() {
    log "INFO" "Step 10: Restarting $NTP_SERVICE..."
    print_status "INFO" "Restarting NTP service: $NTP_SERVICE"
    
    case "$NTP_SERVICE" in
        "xntpd")
            if /etc/init.d/xntpd restart 2>/dev/null; then
                log "INFO" "Service xntpd restarted successfully"
                print_status "INFO" "Service restarted successfully"
                return 0
            fi
            ;;
        "ntpd")
            if /etc/init.d/ntp restart 2>/dev/null; then
                log "INFO" "Service ntpd restarted successfully"
                print_status "INFO" "Service restarted successfully"
                return 0
            fi
            ;;
        "chronyd")
            if /etc/init.d/chrony restart 2>/dev/null; then
                log "INFO" "Service chronyd restarted successfully"
                print_status "INFO" "Service restarted successfully"
                return 0
            fi
            ;;
        "SMF_NTP")
            if svcadm restart svc:/network/ntp 2>/dev/null; then
                log "INFO" "Service SMF NTP restarted successfully"
                print_status "INFO" "Service restarted successfully"
                return 0
            fi
            ;;
    esac
    
    log "ERROR" "Failed to restart NTP service"
    print_status "ERROR" "Failed to restart service"
    return 1
}

###############################################################################
# Main execution flow
###############################################################################
main() {
    log "INFO" "=========================================="
    log "INFO" "NTP Configuration Update Script Started"
    log "INFO" "=========================================="
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log "ERROR" "This script must be run as root"
        print_status "ERROR" "This script requires root privileges. Exiting."
        exit 1
    fi
    
    # Execute workflow steps
    detect_ntp_service || exit 1
    verify_service_running || exit 1
    find_ntp_config || exit 1
    test_cmn_connectivity || test_edn_connectivity || exit 1
    check_existing_ips || exit 0  # All IPs exist, nothing to do
    backup_config || exit 1
    insert_missing_ips || exit 1
    verify_changes || exit 1
    restart_ntp_service || exit 1
    
    log "INFO" "=========================================="
    log "INFO" "NTP Configuration Update Completed Successfully"
    log "INFO" "=========================================="
    print_status "INFO" "Script execution completed successfully!"
    print_status "INFO" "Log file: $LOGFILE"
    
    exit 0
}

# Trap errors and cleanup
trap 'log "ERROR" "Script interrupted"; exit 1' INT TERM

# Run main function
main "$@"
